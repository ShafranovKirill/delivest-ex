defmodule DelivestWeb.Staff.StaffSessionController do
  use DelivestWeb, :controller
  alias Delivest.Identity

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user" => %{"login" => login, "password" => password}}) do
    case Identity.authenticate(login, password) do
      {:ok, account} ->
        conn
        |> put_session(:staff_id, account.id)
        |> put_flash(:info, gettext("Successfully logged in!"))
        |> redirect(to: "/staff/dashboard")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, gettext("Authentication failed."))
        |> redirect(to: "/staff/auth/login")
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, gettext("Logged out successfully."))
    |> redirect(to: "/staff/auth/login")
  end
end
