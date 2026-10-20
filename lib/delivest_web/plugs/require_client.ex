defmodule DelivestWeb.Plugs.RequireClient do
  @behaviour Plug
  import Plug.Conn

  alias DelivestWeb.Helpers.ApiError

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{assigns: %{current_client: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> ApiError.send_error(:unauthorized, :unauthorized, "Authentication required")
    |> halt()
  end
end
