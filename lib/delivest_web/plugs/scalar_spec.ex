defmodule DelivestWeb.Plugs.ScalarSpec do
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _options) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:ok, Jason.encode!(DelivestWeb.ApiCatalog.scalar_spec("/")))
  end
end
