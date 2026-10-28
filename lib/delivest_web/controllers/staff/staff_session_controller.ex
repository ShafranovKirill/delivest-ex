defmodule DelivestWeb.Staff.StaffSessionController do
  use DelivestWeb, :controller

  require Logger

  alias Delivest.{Audit, Identity}

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user" => %{"login" => login, "password" => password}}) do
    case Identity.authenticate(login, password) do
      {:ok, account} ->
        Audit.record(account, "staff.logged_in", account)

        conn
        |> put_session(:staff_id, account.id)
        |> put_flash(:info, gettext("Successfully logged in!"))
        |> redirect(to: ~p"/staff")

      {:error, :invalid_credentials} ->
        Logger.warning("staff.login_failed login=#{inspect(login)} ip=#{remote_ip(conn)}")

        conn
        |> put_flash(:error, gettext("Authentication failed."))
        |> redirect(to: "/staff/auth/login")
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    if staff = conn.assigns[:current_staff], do: Audit.record(staff, "staff.logged_out", staff)

    conn
    |> clear_session()
    |> put_flash(:info, gettext("Logged out successfully."))
    |> redirect(to: "/staff/auth/login")
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
