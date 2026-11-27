defmodule DelivestWeb.Staff.OrderLive.Orders do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, DeliveryMeasurement, Identity, Intake, LocalTime, Money}
  alias Delivest.Integrations.{Crm, StaffAccess, YandexEda}
  alias Delivest.Oms.{Order, OrderDeadline, Orders}
  alias DelivestWeb.CourierPresence
  alias DelivestWeb.Staff.OrderLive.{OrdersQuery, StatusErrors}

  alias DelivestWeb.Staff.OrderLive.Components.{
    CancelOrderModal,
    IntakeControls,
    OrderCardComponent,
    OrderCustomerModal,
    RevertStatusModal,
    OrdersToolbar,
    StatusTabs
  }

  use Gettext, backend: DelivestWeb.Gettext

  @orders_refresh_interval :timer.seconds(30)

  on_mount {DelivestWeb.Hooks.Permission, "orders.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    if connected?(socket) do
      Orders.subscribe(branch_id)
      Intake.subscribe(branch_id)
      Couriers.subscribe(branch_id)
      CourierPresence.subscribe(branch_id)
      schedule_orders_refresh()
    end

    {:ok, branch} = Identity.get_branch(branch_id, preload: :info)
    couriers = Couriers.list_couriers(branch_id)
    {own_couriers_enabled, estimable} = courier_capabilities(branch_id)

    {:ok,
     socket
     |> assign(
       order_to_delete: nil,
       order_to_cancel: nil,
       order_to_revert: nil,
       order_customer: nil,
       shown_id: nil,
       shown_order: nil,
       crm_retry_at: nil,
       crm_retry_timer: nil,
       crm_retry_token: nil,
       crm_retry_poll_ms: 1_000,
       delivery_minutes: OrderDeadline.delivery_minutes(branch_id),
       couriers: couriers,
       estimable: estimable,
       own_couriers_enabled: own_couriers_enabled,
       pickup: branch.info,
       printing: Delivest.Printing.settings(branch_id),
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
      shown_id: params["id"],
      order_customer: nil
    )
    |> load()
  end

  defp load(socket) do
    %{filters: filters, page: page} = socket.assigns

    case Orders.paginate_orders(filters, page) do
      {:ok, {orders, meta}} ->
        counts = Orders.count_by_status(filters)

        socket =
          socket
          |> assign(meta: meta, counts: counts, page_title: gettext("Orders"))
          |> assign(receipt_alerts: receipt_alerts(socket.assigns.current_branch.id))
          |> assign(
            intake: Intake.status(socket.assigns.current_branch.id),
            delivery_minutes: OrderDeadline.delivery_minutes(socket.assigns.current_branch.id)
          )
          |> assign(
            busy_mode: Delivest.Integrations.YandexEda.busy_mode(socket.assigns.current_branch.id)
          )
          |> stream(:orders, Enum.reject(orders, &(&1.id == socket.assigns.shown_id)),
            reset: true
          )
          |> assign_shown()

        {:noreply, refresh_crm_retry(socket, true)}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/orders")}
    end
  end

  defp courier_capabilities(branch_id) do
    case Couriers.settings(branch_id).source do
      :staff -> {Couriers.own_enabled?(branch_id), false}
      :yandex -> {false, StaffAccess.allowed?(:yandex_delivery)}
      _ -> {false, false}
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

  def handle_event("show_customer", %{"id" => id}, socket) do
    staff = Identity.fresh_staff(socket.assigns.current_staff)
    branch = socket.assigns.current_branch

    with :ok <- Identity.authorize(staff, "orders.read", branch.id),
         {:ok, %Order{deleted_at: nil} = order} <- fetch_branch_order(socket, id) do
      customer = OrderCustomerModal.load(staff, branch, order)
      {:noreply, assign(socket, :order_customer, customer)}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Order not found"))}
    end
  end

  def handle_event("hide_customer", _, socket),
    do: {:noreply, assign(socket, :order_customer, nil)}

  def handle_event("advance", %{"order-id" => id, "to" => to}, socket) do
    with {:ok, to} <- StatusErrors.parse_status(to),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _order} <- Orders.advance_order(order, to, staff(socket)) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_delivery_step", params, socket) do
    with %{"order_id" => id, "delivery_id" => delivery_id, "to" => target, "reason" => reason} <-
           params,
         {:ok, to} when to in [:delivering, :completed] <- StatusErrors.parse_status(target),
         {:ok, delivery_id} <- Ecto.UUID.cast(delivery_id),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:staff, %Identity.Staff{}} = actor <- staff(socket),
         {:ok, _order} <-
           Orders.advance_order(order, to, actor,
             delivery_id: delivery_id,
             reason: reason
           ) do
      load(socket)
    else
      {:error, _} = error -> failed(socket, error)
      {:staff, nil} -> failed(socket, :forbidden)
      _ -> failed(socket, :delivery_changed)
    end
  end

  def handle_event("confirm_delivery_promise", %{"order_id" => id, "promise" => params}, socket) do
    branch_id = socket.assigns.current_branch.id
    promised_at = LocalTime.parse(Map.get(params, "at", ""), branch_id)

    with %DateTime{} = at <- promised_at,
         {:ok, _order} <-
           DeliveryMeasurement.confirm_promise(
             Identity.fresh_staff(socket.assigns.current_staff),
             branch_id,
             id,
             at,
             Map.get(params, "reason")
           ) do
      load(socket)
    else
      _ ->
        socket
        |> put_flash(
          :error,
          "Не удалось подтвердить время доставки. Проверьте время и причину изменения."
        )
        |> load()
    end
  end

  def handle_event("find_courier", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <-
           Couriers.find(Identity.fresh_staff(socket.assigns.current_staff), order) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("estimate_delivery", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, estimate} <-
           Couriers.estimate(Identity.fresh_staff(socket.assigns.current_staff), order) do
      {:noreply, put_flash(socket, estimate_kind(estimate), estimate_message(estimate, socket))}
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_paid_cancel", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <-
           Couriers.confirm_cancel(Identity.fresh_staff(socket.assigns.current_staff), order) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("assign_courier", %{"order-id" => id, "courier_id" => courier_id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <-
           Couriers.assign(Identity.fresh_staff(socket.assigns.current_staff), order, courier_id) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("unassign_courier", %{"order-id" => id}, socket) do
    with {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _delivery} <-
           Couriers.unassign(Identity.fresh_staff(socket.assigns.current_staff), order) do
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
           Orders.revert_order_status(
             order,
             Identity.fresh_staff(socket.assigns.current_staff),
             reason
           ) do
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
             Identity.fresh_staff(socket.assigns.current_staff)
           ) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("retry_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, "finance.receipts_retry", &Delivest.Fiscal.retry/2)

  def handle_event("correct_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, "admin", &Delivest.Fiscal.correct/2)

  def handle_event("refund_receipt", %{"id" => id}, socket),
    do: receipt_action(socket, id, "finance.receipts_refund", &Delivest.Fiscal.refund/2)

  def handle_event("courier_code", %{"order-id" => id, "code" => code}, socket) do
    Identity.fresh_staff(socket.assigns.current_staff)
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
         {:ok, _} <-
           Orders.soft_delete_order(order, Identity.fresh_staff(socket.assigns.current_staff)) do
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
  def handle_info(:features_changed, socket) do
    branch_id = socket.assigns.current_branch.id
    {own_couriers_enabled, estimable} = courier_capabilities(branch_id)

    socket
    |> assign(
      own_couriers_enabled: own_couriers_enabled,
      estimable: estimable
    )
    |> load()
  end

  def handle_info({Orders, [:order, _event], _order}, socket), do: load(socket)

  def handle_info(:refresh_orders, socket) do
    schedule_orders_refresh()
    load(socket)
  end

  def handle_info({:intake_changed, branch_id}, socket) do
    {:noreply, assign(socket, :intake, Intake.status(branch_id))}
  end

  def handle_info({:deliveries_changed, _branch_id}, socket), do: load(socket)

  def handle_info(
        {:crm_retry_refresh, id, token},
        %{assigns: %{shown_id: id, crm_retry_token: token}} = socket
      ) do
    {:noreply, socket |> assign_shown() |> refresh_crm_retry()}
  end

  def handle_info({:crm_retry_refresh, _id, _token}, socket), do: {:noreply, socket}

  def handle_info({:courier_presence, branch_id}, socket) do
    positions = CourierPresence.positions(branch_id, socket.assigns.couriers)

    {:noreply,
     socket
     |> assign(positions: positions)
     |> push_event("courier_positions", %{positions: positions})}
  end

  defp schedule_orders_refresh do
    Process.send_after(self(), :refresh_orders, @orders_refresh_interval)
  end

  defp refresh_crm_retry(socket, reset_poll? \\ false) do
    if socket.assigns.crm_retry_timer, do: Process.cancel_timer(socket.assigns.crm_retry_timer)

    order = socket.assigns.shown_order
    at = Crm.next_retry_at(order)
    poll_ms = if reset_poll?, do: 1_000, else: socket.assigns.crm_retry_poll_ms

    socket =
      assign(socket,
        crm_retry_at: at,
        crm_retry_timer: nil,
        crm_retry_token: nil,
        crm_retry_poll_ms: if(at, do: 1_000, else: min(poll_ms * 2, 8_000))
      )

    if connected?(socket) and Crm.cash_closed?(order) and order.crm.status == "pending" do
      delay =
        case at do
          nil -> poll_ms
          at -> max(DateTime.diff(at, DateTime.utc_now(), :millisecond) + 1_000, 1_000)
        end

      token = make_ref()

      timer =
        Process.send_after(self(), {:crm_retry_refresh, socket.assigns.shown_id, token}, delay)

      assign(socket, crm_retry_timer: timer, crm_retry_token: token)
    else
      socket
    end
  end

  defp courier_code_error(:forbidden), do: gettext("Permission denied")
  defp courier_code_error(:empty_code), do: gettext("Enter the courier code")
  defp courier_code_error(:no_attempts), do: gettext("No attempts left to check the courier code")

  defp courier_code_error(:push_not_configured),
    do: gettext("Yandex Eda push access is not set up")

  defp courier_code_error(_reason), do: gettext("Yandex Eda did not accept the request")

  defp receipt_action(socket, id, permission, action) do
    branch_id = socket.assigns.current_branch.id

    with :ok <- authorize(socket, permission),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %{branch_id: ^branch_id} = receipt <- Delivest.Fiscal.get(uuid),
         {:ok, _receipt} <- action.(receipt, Identity.fresh_staff(socket.assigns.current_staff)) do
      load(socket)
    else
      {:error, :forbidden} = error ->
        failed(socket, error)

      {:error, :refund_online_payment} ->
        socket
        |> put_flash(
          :error,
          gettext("Refund the YooKassa payment first. The receipt is issued after confirmation.")
        )
        |> load()

      _error ->
        socket |> put_flash(:error, gettext("Failed to issue the receipt")) |> load()
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

  defp staff(socket), do: {:staff, Identity.fresh_staff(socket.assigns.current_staff)}

  defp patch(query, socket),
    do: {:noreply, push_patch(socket, to: orders_path(socket.assigns.current_branch, query))}

  defp authorize(socket, permission) do
    if Identity.can?(Identity.fresh_staff(socket.assigns.current_staff), permission),
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

  def staff_page_header(assigns), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <div id="orders-page" phx-hook="WorkspaceFullscreen" class="space-y-3 p-2 sm:p-3">
      <.card id="orders-filters" class="orders-toolbar gap-2 p-2 sm:p-3">
        <OrdersToolbar.orders_toolbar
          selected={@selected}
          reset_path={orders_path(@current_branch, %{})}
        >
          <StatusTabs.status_tabs
            counts={@counts}
            selected={@selected.status}
            path_fn={&tab_path(@current_branch, @query, &1)}
          />
        </OrdersToolbar.orders_toolbar>
        <button
          id="orders-fullscreen"
          type="button"
          class="btn btn-sm btn-outline"
          aria-label={gettext("Full screen")}
          aria-pressed="false"
          data-fullscreen-toggle
          data-enter-label={gettext("Full screen")}
          data-exit-label={gettext("Exit full screen")}
        >
          <.icon name="hero-arrows-pointing-out" class="size-4 orders-fullscreen-enter" />
          <.icon name="hero-arrows-pointing-in" class="size-4 orders-fullscreen-exit" />
        </button>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/orders/new?#{@query}"}
          class="orders-new-order staff-page-primary-action btn btn-sm btn-primary"
          aria-label={gettext("New Order")}
        >
          <.icon name="hero-plus" class="size-4" />
          <span>{gettext("New Order")}</span>
        </.link>
      </.card>
      <IntakeControls.plate
        intake={@intake}
        branch_id={@current_branch.id}
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
          navigate={~p"/staff/b/#{@current_branch}/finance/receipts?status=problem"}
          class="btn btn-sm"
        >
          {gettext("Open receipts")}
        </.link>
      </div>

      <div id="orders" phx-update="stream" phx-hook=".OrdersReturnContext" class="space-y-3">
        <div id="orders-empty" class="hidden only:block">
          <.empty_state title={gettext("No orders here yet")} class="py-16" />
        </div>
        <OrderCardComponent.render_card
          :for={{id, order} <- @streams.orders}
          id={id}
          order={order}
          current_staff={@current_staff}
          current_branch={@current_branch}
          printing={@printing}
          return_query={@query}
          delivery_minutes={@delivery_minutes}
          couriers={@couriers}
          estimable={@estimable}
          own_couriers_enabled={@own_couriers_enabled}
          capability_revision={@capability_revision}
        />
      </div>

      <.pagination
        meta={@meta}
        path_fn={&orders_path(@current_branch, Map.merge(@query, &1))}
        page_sizes={[25, 50, 100]}
      />

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
          expanded={true}
          current_staff={@current_staff}
          current_branch={@current_branch}
          printing={@printing}
          return_query={@query}
          delivery_minutes={@delivery_minutes}
          couriers={@couriers}
          estimable={@estimable}
          own_couriers_enabled={@own_couriers_enabled}
          capability_revision={@capability_revision}
          positions={@positions}
          pickup={@pickup}
          crm_retry_at={@crm_retry_at}
        />
      </.slide_over>

      <OrderCustomerModal.customer_modal
        :if={@order_customer}
        customer={@order_customer}
        current_branch={@current_branch}
        return_query={@query}
      />

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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".OrdersReturnContext">
        export default {
          mounted() {
            this.returnContext = null
            this.page = this.el.closest('#orders-page')
            this.drawerOpen = this.drawerIsOpen()
            this.onOpen = (event) => {
              if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey ||
                  event.shiftKey || event.altKey || !(event.target instanceof Element)) return
              const link = event.target.closest('[id^="order-view-"]')
              if (!link || !this.el.contains(link)) return

              const fullscreen = this.page.matches(':fullscreen')
              this.returnContext = {
                id: link.id,
                fullscreen,
                scrollTop: fullscreen ? this.page.scrollTop : window.scrollY
              }
            }
            this.el.addEventListener('click', this.onOpen)
            if (this.drawerOpen) this.focusDrawerClose()
          },
          updated() {
            const open = this.drawerIsOpen()
            if (open && !this.drawerOpen) this.focusDrawerClose()
            if (!open && this.drawerOpen && this.returnContext) {
              const context = this.returnContext
              this.returnContext = null
              requestAnimationFrame(() => {
                if (context.fullscreen) this.page.scrollTop = context.scrollTop
                else window.scrollTo(0, context.scrollTop)
                document.getElementById(context.id)?.focus({ preventScroll: true })
              })
            }
            this.drawerOpen = open
          },
          destroyed() {
            this.el.removeEventListener('click', this.onOpen)
          },
          drawerIsOpen() {
            return this.page.querySelector('#order-slideover-toggle')?.checked === true
          },
          focusDrawerClose() {
            requestAnimationFrame(() => {
              this.page.querySelector('#order-slideover-toggle + .drawer-side button')?.focus()
            })
          }
        }
      </script>
    </div>
    """
  end
end
