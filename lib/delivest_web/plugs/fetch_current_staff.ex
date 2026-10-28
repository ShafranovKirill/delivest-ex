defmodule DelivestWeb.Plugs.FetchCurrentStaff do
  @behaviour Plug
  import Plug.Conn
  alias Delivest.Identity
  alias DelivestWeb.KitchenSession

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, :staff_id) do
      nil ->
        case KitchenSession.restore(conn) do
          {:ok, conn, staff} -> assign(conn, :current_staff, staff)
          :error -> assign(conn, :current_staff, nil)
        end

      staff_id ->
        case Identity.get_staff(staff_id, preload: [:role, :branches]) do
          {:ok, staff} ->
            assign(conn, :current_staff, staff)

          _ ->
            conn
            |> delete_session(:staff_id)
            |> assign(:current_staff, nil)
        end
    end
  end
end
