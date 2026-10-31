defmodule Delivest.Integrations.AtolOnline.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.TokenCache

  @host "https://online.atol.ru/possystem/v5/"
  @sandbox "https://testonline.atol.ru/possystem/v5/"
  @kkt_host "https://online.atol.ru/api/"
  @token_ttl 86_400

  def token(settings) do
    "getToken"
    |> Client.post(%{login: settings.login, pass: settings.password}, options(settings, nil))
    |> handle()
    |> case do
      {:ok, %{"token" => token}} when is_binary(token) -> {:ok, token, @token_ttl}
      {:ok, body} -> {:error, {:atol, error_code(body), nil}}
      error -> error
    end
  end

  def register(settings, operation, body),
    do: authorized(settings, &post(settings, "#{settings.group_code}/#{operation}", body, &1))

  def report(settings, uuid),
    do: authorized(settings, &get(settings, "#{settings.group_code}/report/#{uuid}", &1))

  def kkt_info(settings) do
    TokenCache.run(
      {:atol_kkt, settings.login},
      fn -> kkt_token(settings) end,
      fn token ->
        "kkt/v1/cash-registers"
        |> Client.get([limit: 100], kkt_options(token))
        |> kkt_registers(settings)
      end,
      &kkt_expired?/1
    )
  end

  defp kkt_token(settings) do
    case Client.post(
           "auth/v1/gettoken",
           %{login: settings.login, pass: settings.password},
           kkt_options(nil)
         ) do
      {:ok, %{"token" => token}} when is_binary(token) -> {:ok, token, @token_ttl}
      {:ok, body} -> {:error, {:atol, error_code(body), nil}}
      error -> error
    end
  end

  defp kkt_registers({:ok, %{"_embedded" => registers}}, settings) when is_list(registers) do
    {:ok,
     for(
       %{"data" => %{"groupCode" => group} = data} <- registers,
       group == settings.group_code,
       do: data
     )}
  end

  defp kkt_registers({:ok, body}, _settings), do: {:error, {:atol, nil, inspect(body)}}
  defp kkt_registers(error, _settings), do: error

  defp kkt_expired?({:error, {:http_error, 401, _body}}), do: true
  defp kkt_expired?(_result), do: false

  defp kkt_options(token) do
    headers = if token, do: [{"token", token}], else: []

    [
      base_url: kkt_host(),
      journal: :atol,
      headers: [{"accept", "application/hal+json"} | headers]
    ]
  end

  defp kkt_host do
    case Application.get_env(:delivest, Delivest.Integrations.AtolOnline, [])[:kkt_host] do
      host when is_binary(host) and host != "" -> host
      _default -> @kkt_host
    end
  end

  defp authorized(settings, fun) do
    TokenCache.run({:atol, settings.login}, fn -> token(settings) end, fun, &expired?/1)
  end

  defp expired?({:error, {:atol, 11, _text}}), do: true
  defp expired?(_result), do: false

  defp post(settings, path, body, token),
    do: path |> Client.post(body, options(settings, token)) |> handle()

  defp get(settings, path, token),
    do: path |> Client.get([], options(settings, token)) |> handle()

  defp options(settings, token) do
    headers = if token, do: [{"token", token}], else: []

    [
      base_url: host(settings),
      journal: :atol,
      headers: [{"content-type", "application/json; charset=utf-8"} | headers]
    ]
  end

  defp host(settings) do
    case Application.get_env(:delivest, Delivest.Integrations.AtolOnline, [])[:host] do
      host when is_binary(host) and host != "" -> host
      _default -> if settings.sandbox, do: @sandbox, else: @host
    end
  end

  defp handle({:ok, %{"error" => %{} = error} = body}), do: failure(body, error)

  defp handle({:ok, %{} = body}), do: {:ok, body}
  defp handle({:ok, body}), do: {:error, {:atol, nil, inspect(body)}}

  defp handle({:error, {:http_error, _status, %{"error" => %{} = error} = body}}),
    do: failure(body, error)

  defp handle(error), do: error

  defp failure(%{"uuid" => uuid}, %{"code" => 33}) when is_binary(uuid),
    do: {:ok, %{"uuid" => uuid, "status" => "wait"}}

  defp failure(_body, error), do: {:error, {:atol, error["code"], error["text"]}}

  defp error_code(%{"error" => %{"code" => code}}), do: code
  defp error_code(_body), do: nil
end
