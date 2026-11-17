defmodule Delivest.HTTP.Client do
  require Logger

  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Journal.Mask

  @default_timeout 15_000

  @type method :: :get | :post | :put | :delete | :patch
  @type headers :: [{String.t(), String.t()}] | map()
  @type options :: [
          base_url: String.t(),
          headers: headers(),
          timeout: non_neg_integer(),
          decode_json: boolean(),
          format: :json | :form | :multipart,
          journal: atom(),
          response: :body | :full,
          retry: boolean() | keyword()
        ]

  @doc """
  Performs an integration request, returning `{:ok, body}` by default.

  Set `response: :full` to retain the HTTP status and response headers alongside
  the body on successful responses. This includes accepted/queued 201 and 202
  responses; their status must be checked by the integration before using the body.
  Error tuples keep their existing shape in either mode.
  """
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
      case Keyword.fetch(opts, :retry) do
        {:ok, retry} -> Keyword.put(req_options, :retry, retry)
        :error -> req_options
      end

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

    safe_url = full_url |> journal_url(method, body_or_params) |> Mask.url()
    Logger.info("HTTP >>> #{String.upcase(to_string(method))} #{safe_url}")

    started_at = System.monotonic_time(:millisecond)
    result = Req.request(req_options)
    duration = System.monotonic_time(:millisecond) - started_at

    report_request(Keyword.get(opts, :journal, :unknown), result, duration)

    if provider = Keyword.get(opts, :journal) do
      Journal.outgoing(
        provider,
        method,
        journal_url(full_url, method, body_or_params),
        journal_body(method, body_or_params),
        journal_result(result),
        duration
      )
    end

    case result do
      {:ok, %{status: status, body: body} = response} when status in 200..299 ->
        Logger.info("HTTP <<< [#{status}] Success Response from #{safe_url}")

        case Keyword.get(opts, :response, :body) do
          :full -> {:ok, %{status: status, headers: response.headers, body: body}}
          :body -> handle_response_body(body, decode_json?)
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "HTTP <<< [#{status}] Error Response from #{safe_url}\nBody: #{Mask.body(body)}"
        )

        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error(
          "HTTP <<< Connection Exception on #{safe_url}\nReason: #{transport_reason(exception)}"
        )

        {:error, {:connection_error, connection_message(exception), transport_reason(exception)}}
    end
  end

  defp transport_reason(%{reason: reason}) when is_atom(reason), do: reason
  defp transport_reason(_exception), do: :unknown

  defp connection_message(%Req.TransportError{reason: reason}) when is_atom(reason),
    do: Exception.message(%Req.TransportError{reason: reason})

  defp connection_message(_exception), do: "HTTP connection failed"

  # Transport errors have fixed descriptions. Other exceptions can embed the
  # request (including headers and tokens), so do not persist their inspection.
  defp journal_result({:error, exception}),
    do: {:error, RuntimeError.exception(connection_message(exception))}

  defp journal_result(result), do: result

  defp report_request(provider, {:ok, %{status: status}}, duration) do
    :telemetry.execute(
      [:delivest, :integration, :request],
      %{count: 1, duration: duration},
      %{provider: to_string(provider), status: status}
    )
  end

  defp report_request(provider, {:error, _reason}, duration) do
    :telemetry.execute(
      [:delivest, :integration, :request],
      %{count: 1, duration: duration},
      %{provider: to_string(provider), status: :error}
    )
  end

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
