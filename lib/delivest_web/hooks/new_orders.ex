defmodule DelivestWeb.Hooks.NewOrders do
  import Phoenix.Component
  import Phoenix.LiveView

  alias Delivest.Identity
  alias Delivest.Oms.Orders

  def on_mount(:default, _params, _session, socket) do
    case watched_branch(socket) do
      nil ->
        {:cont, assign(socket, new_orders_count: 0)}

      branch_id ->
        if connected?(socket), do: Orders.subscribe_branch(branch_id)

        {:cont,
         socket
         |> assign(new_orders_count: Orders.count_unconfirmed(branch_id))
         |> attach_hook(:new_orders, :handle_info, &handle_info/2)}
    end
  end

  defp watched_branch(%{assigns: %{current_branch: %{id: branch_id}, current_staff: staff}}),
    do: if(Identity.can?(staff, "orders.read"), do: branch_id)

  defp watched_branch(_socket), do: nil

  defp handle_info({:branch_orders_changed, branch_id}, socket),
    do: {:halt, assign(socket, new_orders_count: Orders.count_unconfirmed(branch_id))}

  defp handle_info(_message, socket), do: {:cont, socket}
end
