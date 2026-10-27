defmodule DelivestWeb.Hooks.NewOrders do
  use Gettext, backend: DelivestWeb.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias Delivest.Identity
  alias Delivest.Integrations.YandexEda
  alias Delivest.Oms.Orders

  @overdue_events ~w(overdue_keep overdue_confirm overdue_cancel)

  def on_mount(:default, _params, _session, socket) do
    case watched_branch(socket) do
      nil ->
        {:cont, assign(socket, new_orders_count: 0, overdue_orders: [])}

      branch_id ->
        if connected?(socket), do: Orders.subscribe_branch(branch_id)

        {:cont,
         socket
         |> assign_counts(branch_id)
         |> attach_hook(:new_orders, :handle_info, &handle_info/2)
         |> attach_hook(:overdue_orders, :handle_event, &handle_event/3)}
    end
  end

  defp watched_branch(%{assigns: %{current_branch: %{id: branch_id}, current_staff: staff}}),
    do: if(Identity.can?(staff, "orders.read"), do: branch_id)

  defp watched_branch(_socket), do: nil

  defp assign_counts(socket, branch_id),
    do:
      assign(socket,
        new_orders_count: Orders.count_unconfirmed(branch_id),
        overdue_orders: YandexEda.overdue_orders(branch_id)
      )

  defp handle_info({:branch_orders_changed, branch_id}, socket),
    do: {:halt, assign_counts(socket, branch_id)}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event(event, %{"id" => order_id}, socket) when event in @overdue_events do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case overdue_action(event, staff, branch.id, order_id) do
        {:ok, _order} -> socket
        {:error, :forbidden} -> put_flash(socket, :error, gettext("Permission denied"))
        {:error, _reason} -> put_flash(socket, :error, gettext("Failed to update the order"))
      end

    {:halt, assign_counts(socket, branch.id)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp overdue_action("overdue_keep", staff, branch_id, order_id),
    do: YandexEda.keep_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_confirm", staff, branch_id, order_id),
    do: YandexEda.confirm_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_cancel", staff, branch_id, order_id),
    do: YandexEda.cancel_unconfirmed(staff, branch_id, order_id)
end
