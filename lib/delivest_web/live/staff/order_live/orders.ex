defmodule DelivestWeb.Staff.OrderLive.Orders do
  use DelivestWeb, :live_view

  alias Delivest.Oms.{Order, Orders}

  on_mount {DelivestWeb.Hooks.Permission, "order.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(order_to_delete: nil)
     |> stream(:orders, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    period = Map.get(params, "period", "all")
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

    order = Orders.get_order!(id)

    case Orders.update_order(order, attrs) do
      {:ok, updated_order} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Order updated successfully"))
         |> stream_insert(:orders, updated_order)}

      {:error, _step, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update order"))}
    end
  end

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    {:noreply, assign(socket, order_to_delete: order)}
  end

  @impl true
  def handle_event("confirm_delete", _, %{assigns: %{order_to_delete: order}} = socket) do
    case Orders.soft_delete_order(order) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Order deleted successfully"))
         |> stream_delete(:orders, order)
         |> assign(order_to_delete: nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete order"))}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, order_to_delete: nil)}

  defp resolve_date_range("today", _, _), do: {Date.utc_today(), Date.utc_today()}

  defp resolve_date_range("tomorrow", _, _),
    do: {Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), 1)}

  defp resolve_date_range("yesterday", _, _),
    do: {Date.add(Date.utc_today(), -1), Date.add(Date.utc_today(), -1)}

  defp resolve_date_range("week", _, _), do: {Date.add(Date.utc_today(), -7), nil}
  defp resolve_date_range("month", _, _), do: {Date.add(Date.utc_today(), -30), nil}
  defp resolve_date_range("custom", from, to), do: {parse_date(from), parse_date(to)}
  defp resolve_date_range(_, _, _), do: {nil, nil}

  defp parse_date(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp format_address(%Order.Address{} = addr) do
    [
      addr.city,
      addr.street,
      addr.house && "#{gettext("d.")} #{addr.house}",
      addr.entrance && "#{gettext("ent.")} #{addr.entrance}",
      addr.floor && "#{gettext("fl.")} #{addr.floor}",
      addr.apartment && "#{gettext("apt.")} #{addr.apartment}",
      addr.intercom && "#{gettext("code")} #{addr.intercom}"
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  defp format_address(_), do: "—"

  defp status_color("created"), do: "bg-info/10 text-info border-info/20"
  defp status_color("preparing"), do: "bg-warning/10 text-warning border-warning/20"
  defp status_color("ready"), do: "bg-accent/10 text-accent border-accent/20"
  defp status_color("delivering"), do: "bg-secondary/10 text-secondary border-secondary/20"
  defp status_color("completed"), do: "bg-success/10 text-success border-success/20"
  defp status_color("cancelled"), do: "bg-error/10 text-error border-error/20"
  defp status_color(_), do: "bg-base-200 text-base-content border-base-300"

  defp format_fulfillment_type(:delivery), do: gettext("Delivery")
  defp format_fulfillment_type(:dine_in), do: gettext("Dine in")
  defp format_fulfillment_type(:pickup), do: gettext("Pickup")
  defp format_fulfillment_type("delivery"), do: gettext("Delivery")
  defp format_fulfillment_type("dine_in"), do: gettext("Dine in")
  defp format_fulfillment_type("pickup"), do: gettext("Pickup")
  defp format_fulfillment_type(_), do: "—"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6 bg-base-200/50 min-h-screen">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Orders")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Manage customer orders, track statuses and process fulfillment.")}
          </p>
        </div>
        <.link navigate={~p"/staff/orders/new"} class="btn btn-primary">
          <.icon name="hero-plus" class="size-5" />
          {gettext("New Order")}
        </.link>
      </div>

      <div class="bg-base-100 p-4 rounded-box border border-base-200 shadow-sm space-y-4">
        <.form
          for={%{}}
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
                {"cancelled", gettext("Cancelled")}
              ] do %>
                <option value={val} selected={@selected_status == val}>{label}</option>
              <% end %>
            </select>
          </div>
        </.form>
      </div>

      <div id="orders" phx-update="stream" class="space-y-3">
        <%= for {id, order} <- @streams.orders do %>
          <div
            id={id}
            class="bg-base-100 rounded-box border border-base-200 shadow-sm overflow-hidden"
          >
            <div class="px-4 py-2.5 bg-base-200/40 border-b border-base-200 flex items-center justify-between gap-4">
              <div class="flex items-center gap-3">
                <span class="font-mono font-bold text-base text-primary">#{order.number}</span>
                <span class="text-xs text-base-content/50 border-l border-base-300 pl-3">
                  {Calendar.strftime(order.inserted_at, "%d.%m.%Y %H:%M")}
                </span>
              </div>

              <div class="flex items-center gap-2">
                <form phx-change="update_order" phx-value-order-id={order.id}>
                  <select
                    name="status"
                    class={[
                      "select select-xs font-medium border",
                      status_color(Atom.to_string(order.status))
                    ]}
                  >
                    <%= for {val, label} <- [
                      {"created", gettext("Created")},
                      {"preparing", gettext("Preparing")},
                      {"ready", gettext("Ready")},
                      {"delivering", gettext("Delivering")},
                      {"completed", gettext("Completed")},
                      {"cancelled", gettext("Cancelled")},
                      {"crm", gettext("Crm")}
                    ] do %>
                      <option
                        value={val}
                        selected={Atom.to_string(order.status) == val}
                        class="bg-base-100 text-base-content"
                      >
                        {label}
                      </option>
                    <% end %>
                  </select>
                </form>

                <.link
                  navigate={~p"/staff/orders/#{order.id}/edit"}
                  class="btn btn-ghost btn-xs btn-square"
                  title={gettext("Edit Order")}
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </.link>
                <button
                  type="button"
                  phx-click="delete_click"
                  phx-value-id={order.id}
                  class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
                  title={gettext("Delete Order")}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <div class="p-4 flex flex-col lg:flex-row lg:items-center justify-between gap-4 text-xs">
              <div class="lg:w-1/5 min-w-0">
                <% phone = (order.client && order.client.phone) || order.customer_phone %>
                <% name = (order.client && order.client.name) || order.customer_name %>

                <%= if phone || name do %>
                  <div class="font-mono font-semibold text-base-content truncate">
                    {phone || "—"}
                  </div>
                  <div class="text-base-content/60 truncate">
                    {name || ""}
                  </div>
                <% else %>
                  <div class="font-semibold text-base-content/50 italic truncate">
                    {gettext("Customer not specified")}
                  </div>
                <% end %>
              </div>

              <div class="lg:w-1/4 min-w-0 border-t lg:border-t-0 lg:border-l border-base-200 pt-2 lg:pt-0 lg:pl-4">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm badge-ghost font-medium uppercase shrink-0">
                    {format_fulfillment_type(order.fulfillment_type)}
                  </span>
                </div>
                <%= if order.fulfillment_type == :delivery do %>
                  <p
                    class="text-base-content/70 truncate mt-0.5"
                    title={format_address(order.address)}
                  >
                    {format_address(order.address)}
                  </p>
                <% end %>
                <%= if order.comment && order.comment != "" do %>
                  <p class="text-base-content/70 truncate mt-0.5" title={order.comment}>
                    <span class="font-semibold">{gettext("Comment:")}</span> {order.comment}
                  </p>
                <% end %>
              </div>

              <div class="lg:w-1/5 flex items-center justify-between lg:justify-start gap-3 border-t lg:border-t-0 lg:border-l border-base-200 pt-2 lg:pt-0 lg:pl-4">
                <form phx-change="update_order" phx-value-order-id={order.id}>
                  <select name="payment_method" class="select select-xs select-bordered font-medium">
                    <option value="cash" selected={order.payment_method == :cash}>
                      {gettext("Cash")}
                    </option>
                    <option value="card_offline" selected={order.payment_method == :card_offline}>
                      {gettext("Card Offline")}
                    </option>
                  </select>
                </form>
                <span class="font-mono font-bold text-base text-base-content shrink-0">
                  {order.total_amount} ₽
                </span>
              </div>

              <div class="lg:w-1/4 border-t lg:border-t-0 lg:border-l border-base-200 pt-2 lg:pt-0 lg:pl-4">
                <details class="group">
                  <summary class="cursor-pointer select-none text-primary font-medium flex items-center justify-between hover:underline">
                    <span>{length(order.items)} {gettext("items")}</span>
                    <span class="text-[10px] bg-base-200 px-2 py-0.5 rounded group-open:hidden">{gettext(
                      "Show"
                    )}</span>
                    <span class="text-[10px] bg-base-200 px-2 py-0.5 rounded hidden group-open:inline">{gettext(
                      "Hide"
                    )}</span>
                  </summary>
                  <div class="mt-2 space-y-1.5 pt-2 border-t border-base-200 max-h-36 overflow-y-auto scrollbar-thin">
                    <%= for item <- order.items do %>
                      <div class="flex justify-between items-center text-[11px]">
                        <span class="truncate pr-2 text-base-content/80">{item.title}</span>
                        <div class="flex items-center gap-2 shrink-0 font-mono">
                          <span class="text-base-content/50">{item.quantity} {gettext("pcs")}</span>
                          <span class="font-medium">{item.price * item.quantity} ₽</span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </details>
              </div>
            </div>
          </div>
        <% end %>
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
