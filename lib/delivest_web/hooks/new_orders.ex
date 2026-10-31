defmodule DelivestWeb.Hooks.NewOrders do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  import Phoenix.Component
  import Phoenix.LiveView

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, YandexEda}
  alias Delivest.Oms.{Kitchen, Orders}
  alias DelivestWeb.KitchenPresence

  @overdue_events ~w(overdue_keep overdue_confirm overdue_cancel)
  @kitchen_tick :timer.minutes(1)

  def on_mount(:default, _params, _session, socket) do
    case watched_branch(socket) do
      nil ->
        {:cont,
         assign(socket,
           new_orders_count: 0,
           overdue_orders: [],
           channel_cancelled_orders: [],
           kitchen_status: nil,
           kitchen_late_orders: []
         )}

      branch_id ->
        if connected?(socket), do: watch(socket, branch_id)

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

  defp watch(socket, branch_id) do
    Orders.subscribe_branch(branch_id)

    if operator?(socket.assigns.current_staff, branch_id) do
      Kitchen.subscribe(branch_id)
      KitchenPresence.subscribe(branch_id)
      Process.send_after(self(), :kitchen_tick, @kitchen_tick)
    end
  end

  defp assign_counts(socket, branch_id) do
    staff = socket.assigns.current_staff

    socket
    |> assign(
      new_orders_count: Orders.count_unconfirmed(branch_id),
      overdue_orders: Enum.filter(YandexEda.overdue_orders(branch_id), &today?/1),
      channel_cancelled_orders: channel_cancelled(staff, branch_id)
    )
    |> assign_kitchen(branch_id)
  end

  defp assign_kitchen(socket, branch_id) do
    if operator?(socket.assigns.current_staff, branch_id) and Kitchen.working?(branch_id),
      do:
        assign(socket,
          kitchen_status: KitchenPresence.status(branch_id),
          kitchen_late_orders: Enum.filter(Kitchen.list_late(branch_id), &today?/1)
        ),
      else: assign(socket, kitchen_status: nil, kitchen_late_orders: [])
  end

  defp today?(order) do
    zone = Delivest.LocalTime.timezone(order.branch_id)

    order.inserted_at |> DateTime.shift_zone!(zone) |> DateTime.to_date() ==
      Delivest.LocalTime.today(zone)
  end

  defp operator?(staff, branch_id),
    do: Identity.authorize(staff, "orders.update", branch_id) == :ok

  defp channel_cancelled(staff, branch_id) do
    if Identity.authorize(staff, "orders.update", branch_id) == :ok,
      do: Orders.list_unacknowledged_cancellations(branch_id),
      else: []
  end

  defp handle_info({:branch_orders_changed, branch_id}, socket),
    do: {:halt, assign_counts(socket, branch_id)}

  defp handle_info({:kitchen_presence, branch_id}, socket),
    do: {:halt, assign_kitchen(socket, branch_id)}

  defp handle_info({:kitchen_changed, _branch_id}, socket), do: {:halt, socket}

  defp handle_info({:kitchen_order_ready, order}, socket) do
    {:halt,
     socket
     |> put_flash(:info, gettext("Order #%{number} is ready", number: Order.short_number(order)))
     |> push_event("kitchen:ready", %{number: Order.short_number(order)})}
  end

  defp handle_info(:kitchen_tick, socket) do
    Process.send_after(self(), :kitchen_tick, @kitchen_tick)
    {:halt, assign_kitchen(socket, socket.assigns.current_branch.id)}
  end

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

  defp handle_event("acknowledge_cancel", %{"id" => order_id}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Orders.acknowledge_branch_cancel(staff, branch.id, order_id) do
        {:ok, _order} -> socket
        {:error, :forbidden} -> put_flash(socket, :error, gettext("Permission denied"))
        {:error, _reason} -> put_flash(socket, :error, gettext("Failed to update the order"))
      end

    {:halt, assign_counts(socket, branch.id)}
  end

  defp handle_event("crm_alert", %{"order_id" => order_id} = params, socket),
    do:
      handle_event(
        "crm_alert",
        params |> Map.delete("order_id") |> Map.put("id", order_id),
        socket
      )

  defp handle_event("crm_alert", %{"id" => order_id, "action" => action} = params, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Crm.resolve_alert(staff, branch.id, order_id, action, params["number"]) do
        {:ok, _order} ->
          socket

        {:error, :forbidden} ->
          put_flash(socket, :error, gettext("Permission denied"))

        {:error, :number_required} ->
          put_flash(socket, :error, gettext("Enter the order number in the CRM"))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("Failed to update the order"))
      end

    {:halt, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp overdue_action("overdue_keep", staff, branch_id, order_id),
    do: YandexEda.keep_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_confirm", staff, branch_id, order_id),
    do: YandexEda.confirm_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_cancel", staff, branch_id, order_id),
    do: YandexEda.cancel_unconfirmed(staff, branch_id, order_id)
end
