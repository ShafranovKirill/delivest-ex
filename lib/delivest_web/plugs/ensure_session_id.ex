defmodule DelivestWeb.Plugs.EnsureSessionId do
  @behaviour Plug
  alias DelivestWeb.Helpers.CookieHelper

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case CookieHelper.get_cookie(conn, "session_id") do
      nil ->
        new_session_id = Ecto.UUID.generate()
        CookieHelper.put_cookie(conn, "session_id", new_session_id)

      _existing_id ->
        conn
    end
  end
end
