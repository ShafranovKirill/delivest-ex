defmodule DelivestWeb.Staff.ClientLive.Show do
  use DelivestWeb, :live_view

  alias Delivest.{Analytics, Identity}
  alias Delivest.Oms.Orders
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  import DelivestWeb.Staff.StatsComponents, only: [stat_card: 1]

  on_mount {DelivestWeb.Hooks.Permission, "clients.read"}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    staff = socket.assigns.current_staff

    case Identity.get_client(staff, id) do
      {:ok, client} ->
        scope = branch_scope(staff)
        can_see_orders = Identity.can?(staff, "orders.read")

        {:ok,
         socket
         |> assign(
           page_title: client.name || client.phone,
           client: client,
           can_see_orders: can_see_orders,
           summary: Analytics.client_summary(client.id, scope),
           orders: if(can_see_orders, do: Orders.list_client_orders(client.id, scope), else: []),
           branches: branches(staff),
           active_branch_id: socket.assigns[:active_branch_id],
           expanded: MapSet.new()
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Client not found"))
         |> push_navigate(to: ~p"/staff/clients")}
    end
  end

  @impl true
  def handle_event("toggle_order", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  defp branch_scope(staff) do
    if Identity.can?(staff, "admin"),
      do: :all,
      else: Enum.map(staff.branches || [], & &1.id)
  end

  defp branches(staff), do: staff |> Identity.list_branch_for_staff() |> Map.new(&{&1.id, &1})

  defp can_edit_order?(assigns, order) do
    Map.has_key?(assigns.branches, order.branch_id) and
      Identity.authorize(assigns.current_staff, "orders.update", order.branch_id) == :ok
  end

  defp items_summary(items) do
    items
    |> Enum.map_join(", ", &"#{&1.title} × #{&1.quantity}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div class="flex items-center gap-4 min-w-0">
          <.link navigate={~p"/staff/clients"} class="btn btn-ghost btn-sm btn-square shrink-0">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div class="avatar avatar-placeholder shrink-0">
            <div class="bg-primary/10 text-primary w-14 rounded-full">
              <span class="text-xl font-bold">
                {(@client.name || @client.phone) |> String.first() |> String.upcase()}
              </span>
            </div>
          </div>
          <div class="min-w-0">
            <h1 class="text-2xl sm:text-3xl font-display font-bold text-base-content truncate">
              {@client.name || gettext("No name")}
            </h1>
            <div class="flex flex-wrap items-center gap-2 mt-1">
              <a
                href={"tel:#{@client.phone}"}
                class="font-mono text-base-content/70 hover:text-primary"
              >
                {@client.phone}
              </a>
              <span
                :if={@client.status == :blocked}
                class="badge badge-error badge-sm text-error-content"
              >
                {gettext("Blocked")}
              </span>
              <span :if={@client.status == :active} class="badge badge-success badge-sm">
                {gettext("Active")}
              </span>
            </div>
          </div>
        </div>

        <.link
          :if={Identity.can?(@current_staff, "clients.update")}
          navigate={~p"/staff/clients/#{@client.id}/edit"}
          class="btn btn-outline btn-sm"
        >
          <.icon name="hero-pencil-square" class="size-4" />
          {gettext("Edit")}
        </.link>
      </div>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <.stat_card icon="hero-shopping-bag" label={gettext("Orders")}>
          {@summary.orders_count}
        </.stat_card>
        <.stat_card icon="hero-banknotes" label={gettext("Total spent")}>
          {OrderHelpers.money(@summary.spent)}
        </.stat_card>
        <.stat_card icon="hero-receipt-percent" label={gettext("Average check")}>
          {OrderHelpers.money(@summary.avg_check)}
        </.stat_card>
        <.stat_card icon="hero-clock" label={gettext("Last order")}>
          {OrderHelpers.local_datetime(@summary.last_order_at)}
        </.stat_card>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
        <div class="space-y-6">
          <.live_component
            :if={@active_branch_id && Identity.can?(@current_staff, "promotions.update")}
            module={DelivestWeb.Staff.ClientLive.ClientCodesComponent}
            id="client-codes"
            client={@client}
            branch_id={@active_branch_id}
            current_staff={@current_staff}
          />
          <div class="bg-base-100 rounded-box border border-base-200 shadow-sm p-4 space-y-3">
            <h2 class="font-bold">{gettext("Favourite products")}</h2>
            <ul :if={@summary.favourites != []} class="space-y-2">
              <li
                :for={item <- @summary.favourites}
                class="flex items-center justify-between gap-3 text-sm"
              >
                <span class="truncate">{item.title}</span>
                <span class="badge badge-ghost badge-sm shrink-0">× {item.quantity}</span>
              </li>
            </ul>
            <p :if={@summary.favourites == []} class="text-sm text-base-content/50">
              {gettext("No orders yet")}
            </p>

            <div class="divider my-1"></div>
            <dl class="text-sm space-y-1.5">
              <div class="flex justify-between gap-3">
                <dt class="text-base-content/60">{gettext("Client since")}</dt>
                <dd>{OrderHelpers.local_datetime(@client.inserted_at)}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-base-content/60">{gettext("First order")}</dt>
                <dd>{OrderHelpers.local_datetime(@summary.first_order_at)}</dd>
              </div>
            </dl>
          </div>
        </div>

        <div class="lg:col-span-2 bg-base-100 rounded-box border border-base-200 shadow-sm">
          <div class="p-4 border-b border-base-200 flex items-center justify-between">
            <h2 class="font-bold">{gettext("Order history")}</h2>
            <span class="text-xs text-base-content/50">{gettext("Last 50 orders")}</span>
          </div>

          <p :if={!@can_see_orders} class="p-6 text-sm text-base-content/60">
            {gettext("You don't have permission to view orders.")}
          </p>

          <p :if={@can_see_orders and @orders == []} class="p-6 text-sm text-base-content/60">
            {gettext("The client has no orders yet.")}
          </p>

          <ul :if={@orders != []} class="divide-y divide-base-200">
            <li :for={order <- @orders} id={"client-order-#{order.id}"}>
              <button
                type="button"
                phx-click="toggle_order"
                phx-value-id={order.id}
                class="w-full p-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-left hover:bg-base-200/40 cursor-pointer"
              >
                <span class="font-mono font-bold">#{order.number}</span>
                <span class="text-sm text-base-content/60">
                  {OrderHelpers.local_datetime(order.inserted_at)}
                </span>
                <span class={[
                  "badge badge-sm border",
                  OrderHelpers.status_color(order.status)
                ]}>
                  {OrderHelpers.status_label(order.status)}
                </span>
                <span class="text-xs text-base-content/60 truncate">
                  {(@branches[order.branch_id] && @branches[order.branch_id].name) || "—"} · {OrderHelpers.fulfillment_label(
                    order.fulfillment_type
                  )}
                </span>
                <span class="ml-auto font-mono font-bold">
                  {OrderHelpers.money(order.total_amount)}
                </span>
                <.icon
                  name={
                    if MapSet.member?(@expanded, order.id),
                      do: "hero-chevron-up",
                      else: "hero-chevron-down"
                  }
                  class="size-4 text-base-content/40"
                />
              </button>

              <div :if={MapSet.member?(@expanded, order.id)} class="px-4 pb-4 space-y-3">
                <ul class="rounded-box bg-base-200/50 p-3 space-y-1.5 text-sm">
                  <li :for={item <- order.items} class="flex justify-between gap-3">
                    <span class="truncate">{item.title} × {item.quantity}</span>
                    <span class="font-mono shrink-0">
                      {OrderHelpers.money(item.price * item.quantity)}
                    </span>
                  </li>
                </ul>
                <p :if={order.promotions != []} class="text-sm text-success">
                  <.icon name="hero-receipt-percent" class="size-4" />
                  {Enum.map_join(order.promotions, ", ", &(&1.code || &1.name))} · −{OrderHelpers.money(
                    order.discount_amount
                  )}
                </p>
                <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
                  <span class="text-base-content/60">
                    {gettext("Payment")}: {OrderHelpers.payment_label(order.payment_method)}
                    <span :if={order.comment}> · {order.comment}</span>
                  </span>
                  <.link
                    :if={Map.has_key?(@branches, order.branch_id)}
                    id={"client-order-open-#{order.id}"}
                    navigate={~p"/staff/b/#{@branches[order.branch_id]}/orders/#{order.id}"}
                    class="btn btn-ghost btn-xs ml-auto"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                    {gettext("Open order")}
                  </.link>
                  <.link
                    :if={can_edit_order?(assigns, order)}
                    navigate={~p"/staff/b/#{@branches[order.branch_id]}/orders/#{order.id}/edit"}
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-pencil-square" class="size-4" />
                    {gettext("Edit Order")}
                  </.link>
                </div>
              </div>

              <p
                :if={!MapSet.member?(@expanded, order.id)}
                class="px-4 pb-3 -mt-2 text-xs text-base-content/50 truncate"
              >
                {items_summary(order.items)}
              </p>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
