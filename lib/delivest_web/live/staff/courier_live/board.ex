defmodule DelivestWeb.Staff.CourierLive.Board do
  use DelivestWeb, :live_view

  on_mount {DelivestWeb.Hooks.GatewayArea, :couriers}

  alias Delivest.Oms.Order

  alias Delivest.{Couriers, Identity}
  alias DelivestWeb.CourierPresence
  alias DelivestWeb.Staff.CourierLive.LocationComponents
  alias DelivestWeb.Staff.OrderLive.{OrderHelpers, StatusErrors}

  on_mount {DelivestWeb.Hooks.Permission, "orders.update"}

  @tick_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    if connected?(socket) do
      Couriers.subscribe(branch_id)
      CourierPresence.subscribe(branch_id)
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok, branch} = Identity.get_branch(branch_id, preload: :info)

    {:ok,
     socket
     |> assign(page_title: gettext("Couriers"), pickup: branch.info)
     |> load()}
  end

  @impl true
  def handle_event("settle", %{"id" => courier_id}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Couriers.settle(staff, branch.id, courier_id) do
        {:ok, settlement} ->
          put_flash(
            socket,
            :info,
            gettext("Accepted %{amount}", amount: OrderHelpers.money(settlement.cash_amount))
          )

        {:error, :nothing_to_settle} ->
          put_flash(socket, :error, gettext("Nothing to accept"))

        error ->
          put_flash(socket, :error, StatusErrors.message(error))
      end

    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:deliveries_changed, _branch_id}, socket), do: {:noreply, load(socket)}
  def handle_info({:courier_presence, _branch_id}, socket), do: {:noreply, locate(socket)}
  def handle_info(:tick, socket), do: {:noreply, locate(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    branch_id = socket.assigns.current_branch.id
    couriers = Couriers.list_couriers(branch_id)

    socket
    |> assign(
      couriers: couriers,
      carrying: Couriers.list_carrying(branch_id),
      balances: Couriers.balances(branch_id, Enum.map(couriers, & &1.id))
    )
    |> locate()
  end

  defp locate(socket) do
    %{current_branch: branch, couriers: couriers} = socket.assigns
    positions = CourierPresence.positions(branch.id, couriers)

    socket
    |> assign(online: CourierPresence.online(branch.id), positions: positions)
    |> push_event("courier_positions", %{positions: positions})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="couriers-board" class="space-y-6 py-4 sm:p-6">
      <.page_header title={gettext("Couriers")} subtitle={@current_branch.name} />

      <LocationComponents.couriers_map
        id="couriers-map"
        from={@pickup}
        positions={@positions}
        class="h-72 sm:h-96"
      />

      <p :if={@couriers == []} id="couriers-empty" class="text-base-content/50">
        {gettext("The branch has no couriers. Give a role with the deliveries permission to staff.")}
      </p>

      <div class="grid gap-3 md:grid-cols-2">
        <.courier_row
          :for={courier <- @couriers}
          courier={courier}
          presence={@online[courier.id]}
          deliveries={Map.get(@carrying, courier.id, [])}
          balance={Map.get(@balances, courier.id, Couriers.empty_balance())}
        />
      </div>
    </div>
    """
  end

  attr :courier, :map, required: true
  attr :presence, :map, default: nil
  attr :deliveries, :list, required: true
  attr :balance, :map, required: true

  defp courier_row(assigns) do
    ~H"""
    <article
      id={"courier-#{@courier.id}"}
      class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
    >
      <header class="flex flex-wrap items-center gap-2">
        <span class={["size-2.5 rounded-full", if(@presence, do: "bg-success", else: "bg-base-300")]} />
        <span class="font-semibold">{@courier.name || @courier.login}</span>
        <span id={"courier-#{@courier.id}-status"} class="text-xs text-base-content/60">
          {if @presence, do: gettext("online"), else: gettext("offline")}
        </span>
        <LocationComponents.location_age
          :if={@presence && @presence.position}
          id={"courier-#{@courier.id}-age"}
          at={@presence.position.at}
        />
        <a :if={@courier.phone} href={"tel:#{@courier.phone}"} class="link link-hover ml-auto text-sm">
          {@courier.phone}
        </a>
      </header>

      <ul :if={@deliveries != []} class="flex flex-wrap gap-2">
        <li :for={delivery <- @deliveries} id={"courier-#{@courier.id}-order-#{delivery.order.id}"}>
          <span class={[
            "badge badge-sm border font-medium",
            OrderHelpers.status_color(delivery.order.status)
          ]}>
            #{Order.short_number(delivery.order)} · {OrderHelpers.status_label(delivery.order.status)}
          </span>
        </li>
      </ul>

      <div
        :if={@balance.orders > 0}
        id={"courier-#{@courier.id}-cash"}
        class="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-box bg-base-200/60 px-3 py-2"
      >
        <span>
          {gettext("Cash")} <b class="font-mono">{OrderHelpers.money(@balance.cash)}</b>
        </span>
        <span class="text-base-content/70">
          {gettext("Terminal")} <span class="font-mono">{OrderHelpers.money(@balance.card)}</span>
        </span>
        <button
          id={"settle-#{@courier.id}"}
          type="button"
          phx-click="settle"
          phx-value-id={@courier.id}
          data-confirm={
            gettext("Accept %{amount} in cash from %{name}?",
              amount: OrderHelpers.money(@balance.cash),
              name: @courier.name || @courier.login
            )
          }
          class="btn btn-sm btn-primary ml-auto"
        >
          {gettext("Accept %{amount}", amount: OrderHelpers.money(@balance.cash))}
        </button>
      </div>
    </article>
    """
  end
end
