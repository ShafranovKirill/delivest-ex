defmodule DelivestWeb.Staff.StaffPushController do
  use DelivestWeb, :controller

  alias Delivest.Push

  def subscribe(%{assigns: %{current_staff: %{} = staff}} = conn, params) do
    case Push.subscribe_staff(staff, attrs(params)) do
      {:ok, _subscription} -> send_resp(conn, :no_content, "")
      {:error, _changeset} -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def subscribe(conn, _params), do: send_resp(conn, :unauthorized, "")

  def unsubscribe(%{assigns: %{current_staff: %{} = staff}} = conn, %{"endpoint" => endpoint})
      when is_binary(endpoint) do
    :ok = Push.unsubscribe_staff(staff, endpoint)
    send_resp(conn, :no_content, "")
  end

  def unsubscribe(conn, _params), do: send_resp(conn, :unauthorized, "")

  defp attrs(params) do
    keys = Map.get(params, "keys") || %{}
    %{endpoint: params["endpoint"], p256dh: keys["p256dh"], auth: keys["auth"]}
  end
end
