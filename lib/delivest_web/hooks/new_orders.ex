defmodule DelivestWeb.Hooks.NewOrders do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  import Phoenix.Component
  import Phoenix.LiveView

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, YandexEda}
  alias Delivest.Integrations.Crm.Reconciliation
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
    do: if(Identity.authorize(staff, "orders.read", branch_id) == :ok, do: branch_id)

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

  defp handle_info(message, socket) do
    case watched_branch(socket) do
      nil ->
        if branch_notification?(message),
          do: {:halt, clear_branch_notifications(socket)},
          else: {:cont, socket}

      branch_id ->
        handle_branch_info(message, branch_id, socket)
    end
  end

  defp branch_notification?(:kitchen_tick), do: true

  defp branch_notification?({kind, _})
       when kind in [
              :branch_orders_changed,
              :kitchen_presence,
              :kitchen_changed,
              :kitchen_order_ready
            ],
       do: true

  defp branch_notification?(_), do: false

  defp clear_branch_notifications(socket),
    do:
      assign(socket,
        new_orders_count: 0,
        overdue_orders: [],
        channel_cancelled_orders: [],
        kitchen_status: nil,
        kitchen_late_orders: []
      )

  defp handle_branch_info({:branch_orders_changed, branch_id}, branch_id, socket),
    do: {:halt, assign_counts(socket, branch_id)}

  defp handle_branch_info({:kitchen_presence, branch_id}, branch_id, socket),
    do: {:halt, assign_kitchen(socket, branch_id)}

  defp handle_branch_info(
         {:kitchen_order_ready, %{branch_id: branch_id} = order},
         branch_id,
         socket
       ) do
    {:halt,
     socket
     |> put_flash(:info, gettext("Order #%{number} is ready", number: Order.short_number(order)))
     |> push_event("kitchen:ready", %{number: Order.short_number(order)})}
  end

  defp handle_branch_info(:kitchen_tick, branch_id, socket) do
    if operator?(socket.assigns.current_staff, branch_id),
      do: Process.send_after(self(), :kitchen_tick, @kitchen_tick)

    {:halt, assign_kitchen(socket, branch_id)}
  end

  defp handle_branch_info(message, _branch_id, socket) do
    if branch_notification?(message), do: {:halt, socket}, else: {:cont, socket}
  end

  defp handle_event(event, _params, %{assigns: %{current_branch: nil}} = socket)
       when event in @overdue_events or event in ["acknowledge_cancel", "crm_alert"] do
    {:halt, put_flash(socket, :error, gettext("Permission denied"))}
  end

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
      case crm_alert_action(staff, branch.id, order_id, action, params) do
        {:ok, _order} ->
          socket

        {:error, :forbidden} ->
          put_flash(socket, :error, gettext("Permission denied"))

        {:error, :number_required} ->
          put_flash(socket, :error, gettext("Enter the order number in the CRM"))

        {:error, :confirmation_required} ->
          put_flash(socket, :error, gettext("Confirm you checked the CRM before sending again."))

        {:error, :not_reconcilable} ->
          put_flash(socket, :error, gettext("This order no longer needs CRM reconciliation."))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("Failed to update the order"))
      end

    {:halt, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp crm_alert_action(staff, branch_id, order_id, "resend", %{"confirmed" => "true"}),
    do: Reconciliation.resolve(staff, branch_id, order_id, "resend")

  defp crm_alert_action(_staff, _branch_id, _order_id, "resend", _params),
    do: {:error, :confirmation_required}

  defp crm_alert_action(staff, branch_id, order_id, "exists", params),
    do: Reconciliation.resolve(staff, branch_id, order_id, "exists", params["number"])

  defp crm_alert_action(staff, branch_id, order_id, action, params),
    do: Crm.resolve_alert(staff, branch_id, order_id, action, params["number"])

  defp overdue_action("overdue_keep", staff, branch_id, order_id),
    do: YandexEda.keep_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_confirm", staff, branch_id, order_id),
    do: YandexEda.confirm_unconfirmed(staff, branch_id, order_id)

  defp overdue_action("overdue_cancel", staff, branch_id, order_id),
    do: YandexEda.cancel_unconfirmed(staff, branch_id, order_id)
end
