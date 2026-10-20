defmodule DelivestWeb.Staff.OrderLive.Orders do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Oms.{Order, Orders}
  alias DelivestWeb.Staff.OrderLive.Components.OrderCardComponent

  use Gettext, backend: DelivestWeb.Gettext

  on_mount {DelivestWeb.Hooks.Permission, "orders.read"}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe()
    end

    {:ok,
     socket
     |> assign(order_to_delete: nil)
     |> stream(:orders, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    period = Map.get(params, "period", "today")
    status = Map.get(params, "status", "")
    custom_from = Map.get(params, "date_from", "")
    custom_to = Map.get(params, "date_to", "")

    {date_from, date_to} = resolve_date_range(period, custom_from, custom_to)
    branch_id = socket.assigns[:current_branch] && socket.assigns.current_branch.id

    orders =
      Orders.list_orders(%{
        branch_id: branch_id,
        status: status,
        date_from: date_from,
        date_to: date_to,
        sort_by: :inserted_at,
        sort_dir: :desc
      })

    {:noreply,
     socket
     |> assign(
       selected_period: period,
       custom_date_from: custom_from,
       custom_date_to: custom_to,
       selected_status: status
     )
     |> stream(:orders, orders, reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      params
      |> Map.take(["period", "status", "date_from", "date_to"])
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/staff/orders?#{query_params}")}
  end

  @impl true
  def handle_event("update_order", %{"order-id" => id} = params, socket) do
    attrs = Map.drop(params, ["order-id", "_target"])

    with :ok <- authorize(socket, "orders.update"),
         {:ok, order} <- fetch_branch_order(socket, id),
         {:ok, updated_order} <-
           Orders.update_order_details(order, attrs, socket.assigns.current_staff) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Order updated successfully"))
       |> stream_insert(:orders, updated_order)}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to update order"))}
    end
  end

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    case fetch_branch_order(socket, id) do
      {:ok, order} -> {:noreply, assign(socket, order_to_delete: order)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to delete order"))}
    end
  end

  @impl true
  def handle_event("confirm_delete", _, %{assigns: %{order_to_delete: %Order{} = order}} = socket) do
    with :ok <- authorize(socket, "orders.delete"),
         {:ok, _} <- Orders.soft_delete_order(order, socket.assigns.current_staff) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Order deleted successfully"))
       |> stream_delete(:orders, order)
       |> assign(order_to_delete: nil)}
    else
      {:error, :forbidden} ->
        {:noreply,
         socket |> assign(order_to_delete: nil) |> put_flash(:error, gettext("Permission denied"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete order"))}
    end
  end

  def handle_event("confirm_delete", _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, order_to_delete: nil)}

  @impl true
  def handle_info({Delivest.Oms.Orders, _event, order}, socket)
      when order.branch_id != socket.assigns.current_branch.id,
      do: {:noreply, socket}

  def handle_info({Delivest.Oms.Orders, [:order, :created], order}, socket) do
    {:noreply, stream_insert(socket, :orders, order, at: 0)}
  end

  def handle_info({Delivest.Oms.Orders, [:order, :updated], order}, socket) do
    if order.deleted_at do
      {:noreply, stream_delete(socket, :orders, order)}
    else
      {:noreply, stream_insert(socket, :orders, order)}
    end
  end

  def handle_info({Delivest.Oms.Orders, [:order, :deleted], order}, socket) do
    {:noreply, stream_delete(socket, :orders, order)}
  end

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

  defp resolve_date_range("today", _, _),
    do: {Delivest.LocalTime.today(), Delivest.LocalTime.today()}

  defp resolve_date_range("tomorrow", _, _),
    do: {Date.add(Delivest.LocalTime.today(), 1), Date.add(Delivest.LocalTime.today(), 1)}

  defp resolve_date_range("yesterday", _, _),
    do: {Date.add(Delivest.LocalTime.today(), -1), Date.add(Delivest.LocalTime.today(), -1)}

  defp resolve_date_range("week", _, _), do: {Date.add(Delivest.LocalTime.today(), -7), nil}
  defp resolve_date_range("month", _, _), do: {Date.add(Delivest.LocalTime.today(), -30), nil}
  defp resolve_date_range("custom", from, to), do: {parse_date(from), parse_date(to)}
  defp resolve_date_range(_, _, _), do: {nil, nil}

  defp parse_date(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 sm:space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Orders")}
        subtitle={gettext("Manage customer orders, track statuses and process fulfillment.")}
      >
        <:actions>
          <.link navigate={~p"/staff/orders/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" />
            {gettext("New Order")}
          </.link>
        </:actions>
      </.page_header>

      <div class="bg-base-100 p-4 rounded-box border border-base-200 shadow-sm space-y-4">
        <.form
          for={%{}}
          id="orders-filter"
          phx-change="filter"
          class="flex flex-col sm:flex-row flex-wrap gap-4 justify-between items-stretch sm:items-center"
        >
          <div class="flex flex-col sm:flex-row flex-wrap items-stretch sm:items-center gap-2 w-full sm:w-auto">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase text-base-content/50 shrink-0">{gettext(
                "Period:"
              )}</span>
              <select name="period" class="select select-bordered select-sm w-full sm:w-48">
                <%= for {val, label} <- [
                  {"all", gettext("All")},
                  {"today", gettext("Today")},
                  {"tomorrow", gettext("Tomorrow")},
                  {"yesterday", gettext("Yesterday")},
                  {"week", gettext("Week")},
                  {"month", gettext("Month")},
                  {"custom", gettext("Custom")}
                ] do %>
                  <option value={val} selected={@selected_period == val}>{label}</option>
                <% end %>
              </select>
            </div>

            <%= if @selected_period == "custom" do %>
              <div class="flex items-center gap-1">
                <input
                  type="date"
                  name="date_from"
                  value={@custom_date_from}
                  class="input input-bordered input-sm w-full sm:w-auto"
                />
                <span class="text-base-content/40">-</span>
                <input
                  type="date"
                  name="date_to"
                  value={@custom_date_to}
                  class="input input-bordered input-sm w-full sm:w-auto"
                />
              </div>
            <% end %>
          </div>

          <div class="flex items-center gap-2 w-full sm:w-auto">
            <span class="text-xs font-bold uppercase text-base-content/50 shrink-0">{gettext(
              "Status:"
            )}</span>
            <select name="status" class="select select-bordered select-sm w-full sm:w-48">
              <option value="">{gettext("All Statuses")}</option>
              <%= for {val, label} <- [
                {"created", gettext("Created")},
                {"preparing", gettext("Preparing")},
                {"ready", gettext("Ready")},
                {"delivering", gettext("Delivering")},
                {"completed", gettext("Completed")},
                {"cancelled", gettext("Cancelled")},
                {"crm", gettext("Sent to CRM")}
              ] do %>
                <option value={val} selected={@selected_status == val}>{label}</option>
              <% end %>
            </select>
          </div>
        </.form>
      </div>

      <div id="orders" phx-update="stream" class="space-y-3">
        <OrderCardComponent.render_card
          :for={{id, order} <- @streams.orders}
          id={id}
          order={order}
          current_staff={@current_staff}
        />
      </div>

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
