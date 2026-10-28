defmodule DelivestWeb.Staff.OrderLive.Orders do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexEda
  alias Delivest.Oms.{Order, OrderDeadline, Orders}
  alias DelivestWeb.Staff.OrderLive.OrdersQuery

  alias DelivestWeb.Staff.OrderLive.Components.{
    CancelOrderModal,
    OrderCardComponent,
    OrdersToolbar,
    StatusTabs
  }

  use Gettext, backend: DelivestWeb.Gettext

  on_mount {DelivestWeb.Hooks.Permission, "orders.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    if connected?(socket), do: Orders.subscribe(branch_id)

    {:ok,
     socket
     |> assign(
       order_to_delete: nil,
       order_to_cancel: nil,
       shown_id: nil,
       shown_order: nil,
       delivery_minutes: OrderDeadline.delivery_minutes(branch_id)
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

  def handle_event("update_order", %{"order-id" => id, "status" => "cancelled"} = params, socket)
      when not is_map_key(params, "cancel_reason") do
    with :ok <- authorize(socket, "orders.update"),
         {:ok, order} <- fetch_branch_order(socket, id) do
      {:noreply, assign(socket, order_to_cancel: order)}
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("update_order", %{"order-id" => id} = params, socket) do
    attrs = Map.drop(params, ["order-id", "_target"])

    with :ok <- authorize(socket, "orders.update"),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, _order} <- Orders.update_order_details(order, attrs, socket.assigns.current_staff) do
      load(socket)
    else
      error -> failed(socket, error)
    end
  end

  def handle_event("confirm_cancel", %{"cancel" => cancel}, socket) do
    %Order{id: id} = socket.assigns.order_to_cancel

    params = %{
      "order-id" => id,
      "status" => "cancelled",
      "cancel_reason" => cancel["reason"],
      "cancel_note" => cancel["note"]
    }

    handle_event("update_order", params, assign(socket, order_to_cancel: nil))
  end

  def handle_event("dismiss_cancel", _params, socket),
    do: socket |> assign(order_to_cancel: nil) |> load()

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

  defp courier_code_error(:forbidden), do: gettext("Permission denied")
  defp courier_code_error(:empty_code), do: gettext("Enter the courier code")
  defp courier_code_error(:no_attempts), do: gettext("No attempts left to check the courier code")

  defp courier_code_error(:push_not_configured),
    do: gettext("Yandex Eda push access is not set up")

  defp courier_code_error(_reason), do: gettext("Yandex Eda did not accept the request")

  defp failed(socket, {:error, :forbidden}),
    do: socket |> put_flash(:error, gettext("Permission denied")) |> load()

  defp failed(socket, _error),
    do: socket |> put_flash(:error, gettext("Failed to update order")) |> load()

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

  @impl true
  def render(assigns) do
    ~H"""
    <div id="orders-page" class="space-y-4 sm:space-y-5 py-4 sm:p-6">
      <.page_header
        title={gettext("Orders")}
        subtitle={gettext("Manage customer orders, track statuses and process fulfillment.")}
      >
        <:actions>
          <.link navigate={~p"/staff/b/#{@current_branch}/orders/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" />
            {gettext("New Order")}
          </.link>
        </:actions>
      </.page_header>

      <.card class="p-3 sm:p-4 space-y-3">
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
        />
      </div>

      <.pagination meta={@meta} path_fn={&orders_path(@current_branch, Map.merge(@query, &1))} />

      <.slide_over
        id="order-slideover"
        show={@shown_order != nil}
        wide
        title={@shown_order && gettext("Order #%{number}", number: @shown_order.number)}
        on_close={JS.patch(orders_path(@current_branch, @query))}
      >
        <OrderCardComponent.render_card
          :if={@shown_order}
          id="shown-order"
          order={@shown_order}
          current_staff={@current_staff}
          current_branch={@current_branch}
          delivery_minutes={@delivery_minutes}
        />
      </.slide_over>

      <CancelOrderModal.cancel_order_modal order={@order_to_cancel} />

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
