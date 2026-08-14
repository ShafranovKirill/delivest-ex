defmodule DelivestWeb.Plugs.FetchCurrentStaff do
  @behaviour Plug
  import Plug.Conn
  alias Delivest.Identity

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, :staff_id) do
      nil ->
        assign(conn, :current_staff, nil)

      staff_id ->
        case Identity.get_staff(staff_id) do
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
