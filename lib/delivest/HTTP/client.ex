defmodule Delivest.HTTP.Client do
  require Logger

  alias Delivest.Integrations.Journal

  @default_timeout 15_000

  @type method :: :get | :post | :put | :delete | :patch
  @type headers :: [{String.t(), String.t()}] | map()
  @type options :: [
          base_url: String.t(),
          headers: headers(),
          timeout: non_neg_integer(),
          decode_json: boolean(),
          format: :json | :form | :multipart,
          journal: atom()
        ]

  @spec request(method(), String.t(), keyword() | map() | [{String.t(), String.t()}], options()) ::
          {:ok, term()} | {:error, term()}
  def request(method, url, body_or_params \\ [], opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "")
    full_url = base_url <> url

    timeout = Keyword.get(opts, :timeout, @default_timeout)
    custom_headers = Keyword.get(opts, :headers, [])
    decode_json? = Keyword.get(opts, :decode_json, true)

    req_options = [
      method: method,
      url: full_url,
      receive_timeout: timeout,
      headers: custom_headers
    ]

    req_options = Keyword.merge(req_options, config_options())

    req_options =
      case method do
        :get ->
          Keyword.put(req_options, :params, body_or_params)

        _ ->
          case Keyword.get(opts, :format, :json) do
            :form -> Keyword.put(req_options, :form, body_or_params)
            :multipart -> Keyword.put(req_options, :form_multipart, body_or_params)
            :json -> Keyword.put(req_options, :json, body_or_params)
          end
      end

    Logger.info("HTTP >>> #{String.upcase(to_string(method))} #{full_url}")

    started_at = System.monotonic_time(:millisecond)
    result = Req.request(req_options)

    if provider = Keyword.get(opts, :journal) do
      duration = System.monotonic_time(:millisecond) - started_at

      Journal.outgoing(
        provider,
        method,
        journal_url(full_url, method, body_or_params),
        journal_body(method, body_or_params),
        result,
        duration
      )
    end

    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        Logger.info("HTTP <<< [#{status}] Success Response from #{full_url}")

        handle_response_body(body, decode_json?)

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "HTTP <<< [#{status}] Error Response from #{full_url}\nBody: #{inspect(body, pretty: true)}"
        )

        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error(
          "HTTP <<< Connection Exception on #{full_url}\nReason: #{inspect(exception)}"
        )

        {:error, {:connection_error, Exception.message(exception), transport_reason(exception)}}
    end
  end

  defp transport_reason(%{reason: reason}) when is_atom(reason), do: reason
  defp transport_reason(_exception), do: :unknown

  def get(url, params \\ [], opts \\ []), do: request(:get, url, params, opts)
  def post(url, body \\ [], opts \\ []), do: request(:post, url, body, opts)
  def put(url, body \\ [], opts \\ []), do: request(:put, url, body, opts)
  def delete(url, params \\ [], opts \\ []), do: request(:delete, url, params, opts)

  defp journal_url(url, :get, params) when params not in [[], %{}],
    do: url <> if(String.contains?(url, "?"), do: "&", else: "?") <> URI.encode_query(params)

  defp journal_url(url, _method, _params), do: url

  defp journal_body(:get, _params), do: nil
  defp journal_body(_method, body), do: body

  defp config_options,
    do: :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])

  defp handle_response_body(body, _decode_json?) do
    {:ok, body}
  end
end
