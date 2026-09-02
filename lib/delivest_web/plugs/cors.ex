defmodule DelivestWeb.Plugs.CORS do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    origin = System.get_env("CLIENT_ORIGIN", "http://localhost:5173")

    CORSPlug.call(conn, CORSPlug.init(origin: origin))
  end
end
