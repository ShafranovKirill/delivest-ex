defmodule DelivestWeb.Staff.OrderLive.Orders do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, Identity, LocalTime, Money}
  alias Delivest.Integrations.YandexEda
  alias Delivest.Oms.{Order, OrderDeadline, Orders}
  alias DelivestWeb.CourierPresence
  alias DelivestWeb.Staff.OrderLive.{OrdersQuery, StatusErrors}

  alias DelivestWeb.Staff.OrderLive.Components.{
    CancelOrderModal,
    IntakeControls,
    OrderCardComponent,
    RevertStatusModal,
    OrdersToolbar,
    StatusTabs
  }

  use Gettext, backend: DelivestWeb.Gettext

  on_mount {DelivestWeb.Hooks.Permission, "orders.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    if connected?(socket) do
      Orders.subscribe(branch_id)
      Couriers.subscribe(branch_id)
      CourierPresence.subscribe(branch_id)
    end

    {:ok, branch} = Identity.get_branch(branch_id, preload: :info)
    couriers = Couriers.list_couriers(branch_id)

    {:ok,
     socket
     |> assign(
       order_to_delete: nil,
       order_to_cancel: nil,
       order_to_revert: nil,
       shown_id: nil,
       shown_order: nil,
       delivery_minutes: OrderDeadline.delivery_minutes(branch_id),
       couriers: couriers,
       estimable: Couriers.settings(branch_id).source == :yandex,
       pickup: branch.info,
       positions: CourierPresence.positions(branch_id, couriers)
     )
     |> stream(:orders, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    parsed = OrdersQuery.parse(params, socket.assigns.current_branch.id)

    socket
    |> assign(
      selected: parsed.selected,
      filters: parsed.filters,
      page: parsed.page,
      query: parsed.query,
      shown_id: params["id"]
    )
    |> load()
  end

  defp load(socket) do
    %{filters: filters, page: page} = socket.assigns

    case Orders.paginate_orders(filters, page) do
      {:ok, {orders, meta}} ->
        counts = Orders.count_by_status(filters)

        {:noreply,
         socket
         |> assign(meta: meta, counts: counts, page_title: gettext("Orders"))
         |> assign(receipt_alerts: receipt_alerts(socket.assigns.current_branch.id))
         |> assign(
           intake: Delivest.Intake.status(socket.assigns.current_branch.id),
           delivery_minutes: OrderDeadline.delivery_minutes(socket.assigns.current_branch.id)
         )
         |> assign(
           busy_mode: Delivest.Integrations.YandexEda.busy_mode(socket.assigns.current_branch.id)
         )
         |> stream(:orders, Enum.reject(orders, &(&1.id == socket.assigns.shown_id)), reset: true)
         |> assign_shown()}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/orders")}
    end
  end

  defp assign_shown(%{assigns: %{shown_id: nil}} = socket), do: assign(socket, shown_order: nil)

  defp assign_shown(socket) do
    case fetch_branch_order(socket, socket.assigns.shown_id) do
      {:ok, %Order{deleted_at: nil} = order} ->
        assign(socket, shown_order: order)

      {:ok, %Order{}} ->
        close_shown(socket)

      {:error, :not_found} ->
        socket |> put_flash(:error, gettext("Order not found")) |> close_shown()
    end
  end

  defp close_shown(socket) do
    socket
    |> assign(shown_id: nil, shown_order: nil)
    |> push_patch(to: orders_path(socket.assigns.current_branch, socket.assigns.query))
  end

  @impl true
  def handle_event("filter", params, socket) do
    socket.assigns.query
    |> Map.take(["page_size", "status", "sort"])
    |> Map.merge(OrdersQuery.clean(params))
    |> patch(socket)
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    socket.assigns.query |> Map.put("sort", sort) |> Map.delete("page") |> patch(socket)
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    socket.assigns.query |> Map.put("page_size", size) |> Map.delete("page") |> patch(socket)
  end

  def handle_event("advance", %{"order-id" => id, "to" => to}, socket) do
    with {:ok, to} <- StatusErrors.parse_status(to),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _order} <- Orders.advance_order(order, to, staff(socket)) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("find_courier", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <- Couriers.find(socket.assigns.current_staff, order) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("estimate_delivery", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, estimate} <- Couriers.estimate(socket.assigns.current_staff, order) do
      {:noreply, put_flash(socket, estimate_kind(estimate), estimate_message(estimate, socket))}
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_paid_cancel", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <- Couriers.confirm_cancel(socket.assigns.current_staff, order) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("assign_courier", %{"order-id" => id, "courier_id" => courier_id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <- Couriers.assign(socket.assigns.current_staff, order, courier_id) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("unassign_courier", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <- Couriers.unassign(socket.assigns.current_staff, order) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("cancel_click", %{"order-id" => id}, socket) do
    case fetch_branch_order(socket, id) do
      {:ok, order} -> {:noreply, assign(socket, order_to_cancel: order)}
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_cancel", %{"cancel" => cancel}, socket) do
    attrs = %{"cancel_reason" => cancel["reason"], "cancel_note" => cancel["note"]}

    with %Order{} = order <- socket.assigns.order_to_cancel,
         {:ok, _order} <- Orders.cancel_order(order, staff(socket), attrs) do
      socket |> assign(order_to_cancel: nil) |> load()
    else
      error -> socket |> assign(order_to_cancel: nil) |> failed(error)
    end
  end

  def handle_event("dismiss_cancel", _params, socket),
    do: {:noreply, assign(socket, order_to_cancel: nil)}

  def handle_event("revert_click", %{"order-id" => id}, socket) do
    case fetch_branch_order(socket, id) do
      {:ok, order} -> {:noreply, assign(socket, order_to_revert: order)}
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_revert", %{"revert" => %{"reason" => reason}}, socket) do
    with %Order{} = order <- socket.assigns.order_to_revert,
         {:ok, _order} <-
           Orders.revert_order_status(order, socket.assigns.current_staff, reason) do
      socket |> assign(order_to_revert: nil) |> load()
    else
      error -> socket |> assign(order_to_revert: nil) |> failed(error)
    end
  end

  def handle_event("dismiss_revert", _params, socket),
    do: {:noreply, assign(socket, order_to_revert: nil)}

  def handle_event("update_payment", %{"order-id" => id} = params, socket) do
    with :ok <- authorize(socket, "orders.update"),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _order} <-
           Orders.update_payment_method(
             order,
             Map.take(params, ["payment_method"]),
             socket.assigns.current_staff
           ) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("intake_pause", %{"duration" => duration} = params, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns
    result = Delivest.Intake.pause(staff, branch, duration(duration), params["reason"])
    intake_result(socket, result)
  end

  def handle_event("intake_load", %{"minutes" => minutes, "duration" => duration}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    result =
      Delivest.Intake.start_load(staff, branch, String.to_integer(minutes), duration(duration))

    intake_result(socket, result)
  end

  def handle_event("intake_resume", _params, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns
    intake_result(socket, Delivest.Intake.resume(staff, branch))
  end

  def handle_event("retry_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, &Delivest.Fiscal.retry/2)

  def handle_event("correct_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, &Delivest.Fiscal.correct/2)

  def handle_event("refund_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, &Delivest.Fiscal.refund/2)

  def handle_event("courier_code", %{"order-id" => id, "code" => code}, socket) do
    socket.assigns.current_staff
    |> YandexEda.validate_courier_code(socket.assigns.current_branch.id, id, code)
    |> case do
      {:ok, %{valid: true}} ->
        {:noreply, put_flash(socket, :info, gettext("The courier code is correct"))}

      {:ok, %{attempts_left: left}} when is_integer(left) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Wrong courier code, attempts left: %{count}", count: left)
         )}

      {:ok, _result} ->
        {:noreply, put_flash(socket, :error, gettext("Wrong courier code"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, courier_code_error(reason))}
    end
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    case fetch_branch_order(socket, id) do
      {:ok, order} -> {:noreply, assign(socket, order_to_delete: order)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to delete order"))}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{order_to_delete: %Order{} = order}} = socket) do
    with :ok <- authorize(socket, "orders.delete"),
         {:ok, _} <- Orders.soft_delete_order(order, socket.assigns.current_staff) do
      socket
      |> put_flash(:info, gettext("Order deleted successfully"))
      |> assign(order_to_delete: nil)
      |> load()
    else
      {:error, :forbidden} ->
        {:noreply,
         socket |> assign(order_to_delete: nil) |> put_flash(:error, gettext("Permission denied"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete order"))}
    end
  end

  def handle_event("confirm_delete", _, socket), do: {:noreply, socket}

  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, order_to_delete: nil)}

  @impl true
  def handle_info({Orders, [:order, _event], _order}, socket), do: load(socket)
  def handle_info({:deliveries_changed, _branch_id}, socket), do: load(socket)

  def handle_info({:courier_presence, branch_id}, socket) do
    positions = CourierPresence.positions(branch_id, socket.assigns.couriers)

    {:noreply,
     socket
     |> assign(positions: positions)
     |> push_event("courier_positions", %{positions: positions})}
  end

  defp courier_code_error(:forbidden), do: gettext("Permission denied")
  defp courier_code_error(:empty_code), do: gettext("Enter the courier code")
  defp courier_code_error(:no_attempts), do: gettext("No attempts left to check the courier code")

  defp courier_code_error(:push_not_configured),
    do: gettext("Yandex Eda push access is not set up")

  defp courier_code_error(_reason), do: gettext("Yandex Eda did not accept the request")

  defp duration("end_of_day"), do: :end_of_day
  defp duration(minutes), do: String.to_integer(minutes)

  defp intake_result(socket, {:ok, _status}), do: load(socket)
  defp intake_result(socket, {:error, :forbidden}), do: failed(socket, {:error, :forbidden})

  defp intake_result(socket, _error),
    do: {:noreply, put_flash(socket, :error, gettext("Failed to update the order"))}

  defp receipt_action(socket, id, action) do
    branch_id = socket.assigns.current_branch.id

    with :ok <- authorize(socket, "orders.update"),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %{branch_id: ^branch_id} = receipt <- Delivest.Fiscal.get(uuid),
         {:ok, _receipt} <- action.(receipt, socket.assigns.current_staff) do
      load(socket)
    else
      {:error, :forbidden} = error -> failed(socket, error)
      _error -> socket |> put_flash(:error, gettext("Failed to issue the receipt")) |> load()
    end
  end

  defp estimate_kind(%{loss: 0}), do: :info
  defp estimate_kind(_estimate), do: :error

  defp estimate_message(%{price: price, loss: loss} = estimate, socket) do
    text =
      gettext("Yandex Delivery: %{price}, pickup %{pickup}",
        price: Money.format(price),
        pickup: interval(estimate.pickup_interval, socket.assigns.current_branch)
      )

    if loss > 0,
      do: text <> " " <> gettext("Loss: %{loss}", loss: Money.format(loss)),
      else: text
  end

  defp interval(%{"from" => from, "to" => to}, branch),
    do: "#{clock(from, branch)}–#{clock(to, branch)}"

  defp interval(_interval, _branch), do: "—"

  defp clock(iso, branch) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at |> LocalTime.local(branch) |> Calendar.strftime("%H:%M")
      _error -> iso
    end
  end

  defp failed(socket, error),
    do: socket |> put_flash(:error, StatusErrors.message(error)) |> load()

  defp staff(socket), do: {:staff, socket.assigns.current_staff}

  defp patch(query, socket),
    do: {:noreply, push_patch(socket, to: orders_path(socket.assigns.current_branch, query))}

  defp authorize(socket, permission) do
    if Identity.can?(socket.assigns.current_staff, permission),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp fetch_branch_order(socket, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Order{branch_id: branch_id} = order <- Orders.get_order(uuid),
         true <- branch_id == socket.assigns.current_branch.id do
      {:ok, order}
    else
      _ -> {:error, :not_found}
    end
  end

  defp orders_path(branch, query), do: ~p"/staff/b/#{branch}/orders?#{query}"

  defp tab_path(branch, query, change) do
    query
    |> Map.merge(change)
    |> Map.delete("page")
    |> OrdersQuery.clean()
    |> then(&orders_path(branch, &1))
  end

  defp receipt_alerts(branch_id), do: length(Delivest.Fiscal.pending_alerts(branch_id))

  @impl true
  def render(assigns) do
    ~H"""
    <div id="orders-page" class="space-y-4 sm:space-y-5 py-4 sm:p-6">
      <.page_header
        title={gettext("Orders")}
        subtitle={gettext("Manage customer orders, track statuses and process fulfillment.")}
      >
        <:actions>
          <IntakeControls.menu can_manage={Identity.can?(@current_staff, "orders.update")} />
          <.link navigate={~p"/staff/b/#{@current_branch}/orders/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" />
            {gettext("New Order")}
          </.link>
        </:actions>
      </.page_header>

      <IntakeControls.plate
        intake={@intake}
        branch_id={@current_branch.id}
        can_manage={Identity.can?(@current_staff, "orders.update")}
      />

      <DelivestWeb.Staff.IntegrationLive.YandexEdaBusy.plate
        busy={@busy_mode}
        branch_id={@current_branch.id}
      />

      <div :if={@receipt_alerts > 0} id="receipt-alerts" role="alert" class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          {ngettext(
            "%{count} receipt is not issued",
            "%{count} receipts are not issued",
            @receipt_alerts
          )}
        </span>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/receipts?status=problem"}
          class="btn btn-sm"
        >
          {gettext("Open receipts")}
        </.link>
      </div>

      <.card class="flex flex-col gap-4 p-3 sm:p-4">
        <StatusTabs.status_tabs
          counts={@counts}
          selected={@selected.status}
          path_fn={&tab_path(@current_branch, @query, &1)}
        />
        <OrdersToolbar.orders_toolbar selected={@selected} />
      </.card>

      <div id="orders" phx-update="stream" class="space-y-3">
        <div id="orders-empty" class="hidden only:block">
          <.empty_state title={gettext("No orders here yet")} class="py-16" />
        </div>
        <OrderCardComponent.render_card
          :for={{id, order} <- @streams.orders}
          id={id}
          order={order}
          current_staff={@current_staff}
          current_branch={@current_branch}
          delivery_minutes={@delivery_minutes}
          couriers={@couriers}
          estimable={@estimable}
        />
      </div>

      <.pagination meta={@meta} path_fn={&orders_path(@current_branch, Map.merge(@query, &1))} />

      <.slide_over
        id="order-slideover"
        show={@shown_order != nil}
        wide
        title={@shown_order && gettext("Order #%{number}", number: Order.short_number(@shown_order))}
        on_close={JS.patch(orders_path(@current_branch, @query))}
      >
        <OrderCardComponent.render_card
          :if={@shown_order}
          id="shown-order"
          order={@shown_order}
          current_staff={@current_staff}
          current_branch={@current_branch}
          delivery_minutes={@delivery_minutes}
          couriers={@couriers}
          estimable={@estimable}
          positions={@positions}
          pickup={@pickup}
        />
      </.slide_over>

      <CancelOrderModal.cancel_order_modal order={@order_to_cancel} />
      <RevertStatusModal.revert_status_modal order={@order_to_revert} />

      <.modal
        id="delete-order-modal"
        show={@order_to_delete != nil}
        title={gettext("Delete Order")}
        description={
          gettext("Are you sure you want to delete this order? This action cannot be undone.")
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
