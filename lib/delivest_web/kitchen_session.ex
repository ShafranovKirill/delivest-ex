defmodule DelivestWeb.KitchenSession do
  import Plug.Conn

  alias Delivest.Identity
  alias Delivest.Oms.Kitchen

  @cookie "_delivest_kitchen"
  @max_age 60 * 60 * 24 * 365

  def remember(conn, staff) do
    case Identity.get_staff(staff.id, preload: [:role]) do
      {:ok, staff} ->
        if Kitchen.account?(staff),
          do: put_resp_cookie(conn, @cookie, staff.id, sign: true, max_age: @max_age),
          else: forget(conn)

      _ ->
        forget(conn)
    end
  end

  def forget(conn), do: delete_resp_cookie(conn, @cookie, sign: true)

  def restore(conn) do
    conn = fetch_cookies(conn, signed: [@cookie])

    with staff_id when is_binary(staff_id) <- conn.cookies[@cookie],
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         true <- Kitchen.account?(staff) do
      {:ok, put_session(conn, :staff_id, staff.id), staff}
    else
      _ -> :error
    end
  end
end
