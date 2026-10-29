defmodule DelivestWeb.Plugs.IntegrationJournal do
  import Plug.Conn

  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Journal.Mask

  def init(opts), do: opts

  def call(conn, opts) do
    started_at = System.monotonic_time(:millisecond)
    Journal.reset_context()

    register_before_send(conn, fn conn ->
      Journal.record(%{
        provider: Keyword.get(opts, :provider) || conn.path_params["provider"],
        branch_id: Journal.context()[:branch_id] || conn.path_params[opts[:branch_param]],
        direction: :in,
        method: conn.method,
        url: Mask.path(conn.request_path, conn.path_params),
        status: conn.status,
        duration_ms: System.monotonic_time(:millisecond) - started_at,
        request: Map.drop(conn.params, Map.keys(conn.path_params)),
        response: conn.resp_body && IO.iodata_to_binary(conn.resp_body)
      })

      conn
    end)
  end
end
