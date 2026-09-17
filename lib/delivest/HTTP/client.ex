defmodule Delivest.HTTP.Client do
  require Logger

  @default_timeout 15_000

  @type method :: :get | :post | :put | :delete | :patch
  @type headers :: [{String.t(), String.t()}] | map()
  @type options :: [
          base_url: String.t(),
          headers: headers(),
          timeout: non_neg_integer(),
          decode_json: boolean()
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

    req_options =
      case method do
        :get ->
          Keyword.put(req_options, :params, body_or_params)

        _ ->
          case Keyword.get(opts, :format, :json) do
            :form -> Keyword.put(req_options, :form, body_or_params)
            :json -> Keyword.put(req_options, :json, body_or_params)
          end
      end

    Logger.debug("HTTP Request -> #{String.upcase(to_string(method))} #{full_url}")

    case Req.request(req_options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        handle_response_body(body, decode_json?)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("HTTP Error Response <- Status: #{status}, Body: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error("HTTP Connection Exception -> #{inspect(exception)}")
        {:error, {:connection_error, Exception.message(exception)}}
    end
  end

  def get(url, params \\ [], opts \\ []), do: request(:get, url, params, opts)
  def post(url, body \\ [], opts \\ []), do: request(:post, url, body, opts)
  def put(url, body \\ [], opts \\ []), do: request(:put, url, body, opts)
  def delete(url, params \\ [], opts \\ []), do: request(:delete, url, params, opts)

  defp handle_response_body(body, _decode_json?) do
    {:ok, body}
  end
end
