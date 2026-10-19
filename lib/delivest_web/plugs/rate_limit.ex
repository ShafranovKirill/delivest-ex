defmodule DelivestWeb.Plugs.RateLimit do
  @moduledoc """
  Fixed-window rate limit per client IP, stored in the `:rate_limit_cache` Cachex.

      plug DelivestWeb.Plugs.RateLimit, bucket: :orders, limit: 10, period: :timer.minutes(1)

  Options:
    * `:bucket` - name separating independent limits (required)
    * `:limit` - allowed requests per window (required)
    * `:period` - window length in milliseconds (default 1 minute)
    * `:format` - `:json` (default) or `:text` response body when the limit is hit

  Behind a reverse proxy `remote_ip` is the proxy itself, so for loopback/private
  peers the client address is taken from the last `X-Forwarded-For` entry
  (the one appended by our proxy, which the client cannot forge).
  """
  @behaviour Plug
  import Plug.Conn

  alias DelivestWeb.Helpers.ApiError

  @cache :rate_limit_cache

  @impl Plug
  def init(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      limit: Keyword.fetch!(opts, :limit),
      period: Keyword.get(opts, :period, :timer.minutes(1)),
      format: Keyword.get(opts, :format, :json)
    }
  end

  @impl Plug
  def call(conn, %{bucket: bucket, limit: limit, period: period} = opts) do
    window = div(System.system_time(:millisecond), period)
    key = {bucket, client_ip(conn), window}

    case Cachex.incr(@cache, key) do
      {:ok, 1} ->
        Cachex.expire(@cache, key, period)
        conn

      {:ok, count} when count > limit ->
        reject(conn, opts)

      _ ->
        conn
    end
  end

  defp reject(conn, %{format: :text, period: period}) do
    conn
    |> put_resp_header("retry-after", retry_after(period))
    |> put_resp_content_type("text/plain")
    |> send_resp(:too_many_requests, "Too many requests, please try again later.")
    |> halt()
  end

  defp reject(conn, %{period: period}) do
    conn
    |> put_resp_header("retry-after", retry_after(period))
    |> ApiError.send_error(:too_many_requests, :too_many_requests, "Too many requests")
    |> halt()
  end

  defp retry_after(period), do: period |> div(1000) |> max(1) |> Integer.to_string()

  @doc false
  def client_ip(conn) do
    if trusted_proxy?(conn.remote_ip) do
      case forwarded_ip(conn) do
        nil -> format_ip(conn.remote_ip)
        ip -> ip
      end
    else
      format_ip(conn.remote_ip)
    end
  end

  defp forwarded_ip(conn) do
    conn
    |> get_req_header("x-forwarded-for")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  defp trusted_proxy?({127, _, _, _}), do: true
  defp trusted_proxy?({10, _, _, _}), do: true
  defp trusted_proxy?({172, second, _, _}) when second in 16..31, do: true
  defp trusted_proxy?({192, 168, _, _}), do: true
  defp trusted_proxy?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp trusted_proxy?(_), do: false

  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()
end
