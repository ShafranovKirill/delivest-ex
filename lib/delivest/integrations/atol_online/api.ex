defmodule Delivest.Integrations.AtolOnline.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.TokenCache

  @host "https://online.atol.ru/possystem/v5/"
  @sandbox "https://testonline.atol.ru/possystem/v5/"
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

  defp handle({:ok, %{"error" => %{} = error}}),
    do: {:error, {:atol, error["code"], error["text"]}}

  defp handle({:ok, %{} = body}), do: {:ok, body}
  defp handle({:ok, body}), do: {:error, {:atol, nil, inspect(body)}}

  defp handle({:error, {:http_error, _status, %{"error" => %{} = error}}}),
    do: {:error, {:atol, error["code"], error["text"]}}

  defp handle(error), do: error

  defp error_code(%{"error" => %{"code" => code}}), do: code
  defp error_code(_body), do: nil
end
