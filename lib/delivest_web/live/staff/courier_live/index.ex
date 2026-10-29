defmodule DelivestWeb.Staff.CourierLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Oms.Order

  alias Delivest.{Couriers, Identity}
  alias Delivest.Oms.{OrderDeadline, Orders}
  alias DelivestWeb.CourierPresence
  alias DelivestWeb.Staff.OrderLive.{OrderHelpers, StatusErrors}

  on_mount {DelivestWeb.Hooks.Permission, "orders.deliver"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    if connected?(socket) do
      Couriers.subscribe(branch_id)
      Orders.subscribe(branch_id)
      CourierPresence.track_courier(self(), branch_id, socket.assigns.current_staff)
    end

    {:ok, branch} = Identity.get_branch(branch_id, preload: :info)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Deliveries"),
       pickup: branch.info,
       delivery_minutes: OrderDeadline.delivery_minutes(branch_id)
     )
     |> load()}
  end

  @impl true
  def handle_event("location", %{"lat" => lat, "lng" => lng}, socket)
      when is_number(lat) and is_number(lng) and abs(lat) <= 90 and abs(lng) <= 180 do
    %{current_staff: staff, current_branch: branch} = socket.assigns
    CourierPresence.locate(self(), branch.id, staff, %{lat: lat / 1, lng: lng / 1})
    {:noreply, socket}
  end

  def handle_event("location", _params, socket), do: {:noreply, socket}

  def handle_event(action, %{"id" => id}, socket)
      when action in ~w(take refuse pick_up hand_over) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case run(action, staff, branch.id, id) do
        {:ok, _result} -> socket
        error -> put_flash(socket, :error, StatusErrors.message(error))
      end

    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:deliveries_changed, _branch_id}, socket), do: {:noreply, load(socket)}
  def handle_info({Orders, _event, _order}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp run("take", staff, branch_id, id), do: Couriers.take(staff, branch_id, id)
  defp run("refuse", staff, branch_id, id), do: Couriers.refuse(staff, branch_id, id)
  defp run("pick_up", staff, branch_id, id), do: Couriers.pick_up(staff, branch_id, id)
  defp run("hand_over", staff, branch_id, id), do: Couriers.hand_over(staff, branch_id, id)

  defp load(socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    assign(socket,
      mine: Couriers.list_mine(staff, branch.id),
      open: Couriers.list_open(branch.id),
      balance: Couriers.balance(branch.id, staff.id)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="courier-page" class="mx-auto max-w-2xl space-y-6 py-4 sm:p-6">
      <.page_header title={gettext("Deliveries")} subtitle={@current_branch.name} />

      <p
        id="courier-location"
        phx-hook="CourierLocation"
        phx-update="ignore"
        class="group -mt-4 text-sm"
      >
        <span class="hidden items-center gap-1 text-success group-data-[state=on]:flex">
          <.icon name="hero-map-pin" class="size-4" /> {gettext("The operator sees you on the map")}
        </span>
        <span class="hidden items-center gap-1 text-error group-data-[state=denied]:flex">
          <.icon name="hero-exclamation-triangle" class="size-4" />
          {gettext("Allow access to the location so the operator sees you on the map")}
        </span>
        <span class="hidden items-center gap-1 text-warning group-data-[state=unavailable]:flex group-data-[state=unsupported]:flex">
          <.icon name="hero-exclamation-triangle" class="size-4" />
          {gettext("The location is not available on this device")}
        </span>
      </p>

      <DelivestWeb.StaffPushToggle.staff_push_toggle
        id="courier-push-toggle"
        class="btn btn-outline btn-block justify-center data-[state=on]:btn-ghost data-[state=on]:btn-sm data-[state=on]:text-success"
      />

      <.cash_summary balance={@balance} />

      <section id="courier-mine" class="space-y-3">
        <h2 class="text-sm font-bold uppercase text-base-content/60">{gettext("My orders")}</h2>
        <p :if={@mine == []} id="courier-mine-empty" class="text-base-content/50">
          {gettext("You have no orders")}
        </p>
        <.delivery_card
          :for={delivery <- @mine}
          delivery={delivery}
          pickup={@pickup}
          deadline={OrderDeadline.at(delivery.order, @delivery_minutes)}
          mine
        />
      </section>

      <section id="courier-open" class="space-y-3">
        <h2 class="text-sm font-bold uppercase text-base-content/60">{gettext("New requests")}</h2>
        <p :if={@open == []} id="courier-open-empty" class="text-base-content/50">
          {gettext("No new requests")}
        </p>
        <.delivery_card
          :for={delivery <- @open}
          delivery={delivery}
          pickup={@pickup}
          deadline={OrderDeadline.at(delivery.order, @delivery_minutes)}
        />
      </section>
    </div>
    """
  end

  attr :balance, :map, required: true

  defp cash_summary(assigns) do
    ~H"""
    <section
      :if={@balance.orders > 0}
      id="courier-cash"
      class="grid grid-cols-2 gap-2 rounded-box border border-base-300 bg-base-100 p-4"
    >
      <div>
        <p class="text-xs uppercase text-base-content/50">{gettext("Cash on hand")}</p>
        <p id="courier-cash-amount" class="font-mono text-2xl font-black">
          {OrderHelpers.money(@balance.cash)}
        </p>
      </div>
      <div>
        <p class="text-xs uppercase text-base-content/50">{gettext("By terminal")}</p>
        <p class="font-mono text-2xl font-bold text-base-content/70">
          {OrderHelpers.money(@balance.card)}
        </p>
      </div>
      <p class="col-span-2 text-sm text-base-content/60">
        {ngettext(
          "%{count} order since the last handover",
          "%{count} orders since the last handover",
          @balance.orders
        )}
      </p>
    </section>
    """
  end

  attr :delivery, :map, required: true
  attr :pickup, :map, default: nil
  attr :deadline, DateTime, required: true
  attr :mine, :boolean, default: false

  defp delivery_card(assigns) do
    order = assigns.delivery.order

    assigns =
      assign(assigns,
        order: order,
        address: order.address,
        client: order.client,
        collect: if(order.payment_method == :online, do: 0, else: order.total_amount)
      )

    ~H"""
    <article
      id={"delivery-#{@delivery.id}"}
      class="overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm"
    >
      <header class="flex items-center justify-between gap-2 border-b border-base-200 bg-base-200/40 px-4 py-3">
        <div class="flex items-center gap-2">
          <span class="font-mono text-xl font-black">#{Order.short_number(@order)}</span>
          <span class={["badge badge-sm border font-medium", OrderHelpers.status_color(@order.status)]}>
            {OrderHelpers.status_label(@order.status)}
          </span>
        </div>
        <span class="flex items-center gap-1 font-mono text-lg font-bold">
          <.icon name="hero-clock" class="size-4 text-base-content/50" />
          {OrderHelpers.local_time(@deadline)}
        </span>
      </header>

      <div class="space-y-3 p-4">
        <div :if={@pickup} class="flex gap-2">
          <.icon name="hero-building-storefront" class="size-5 shrink-0 text-base-content/40" />
          <div>
            <p class="text-xs uppercase text-base-content/50">{gettext("Pick up")}</p>
            <p>{@pickup.address || "—"}</p>
          </div>
        </div>

        <div class="flex gap-2">
          <.icon name="hero-map-pin" class="size-5 shrink-0 text-primary" />
          <div class="min-w-0">
            <p class="text-xs uppercase text-base-content/50">{gettext("Deliver to")}</p>
            <p class="text-lg font-semibold break-words">
              {street_line(@address)}
            </p>
            <p :if={@address} class="flex flex-wrap gap-x-3 text-base-content/80">
              <span :if={present?(@address.entrance)}>
                {gettext("entrance")} <b>{@address.entrance}</b>
              </span>
              <span :if={present?(@address.floor)}>
                {gettext("floor")} <b>{@address.floor}</b>
              </span>
              <span :if={present?(@address.apartment)}>
                {gettext("apartment")} <b>{@address.apartment}</b>
              </span>
              <span :if={present?(@address.intercom)}>
                {gettext("intercom")} <b>{@address.intercom}</b>
              </span>
            </p>
            <p :if={@address && present?(@address.comment)} class="text-base-content/70">
              {@address.comment}
            </p>
          </div>
        </div>

        <div :if={@mine and @client} class="flex items-center gap-2">
          <.icon name="hero-user" class="size-5 shrink-0 text-base-content/40" />
          <span>{@client.name}</span>
          <a
            :if={@client.phone}
            href={"tel:#{@client.phone}"}
            class="btn btn-sm btn-outline ml-auto font-mono"
          >
            <.icon name="hero-phone" class="size-4" /> {@client.phone}
          </a>
        </div>

        <p
          :if={present?(@order.comment)}
          class="rounded-box bg-warning/15 px-3 py-2 text-base-content"
        >
          {@order.comment}
        </p>

        <div class="flex items-center justify-between rounded-box bg-base-200/60 px-3 py-2">
          <span class="text-base-content/70">{OrderHelpers.payment_label(@order.payment_method)}</span>
          <span id={"delivery-collect-#{@delivery.id}"} class="font-mono text-xl font-black">
            {if @collect > 0, do: OrderHelpers.money(@collect), else: gettext("Paid")}
          </span>
        </div>

        <div
          :if={@mine and located?(@address)}
          id={"delivery-map-#{@delivery.id}"}
          phx-hook="CourierMap"
          phx-update="ignore"
          data-from-lat={@pickup && @pickup.latitude}
          data-from-lng={@pickup && @pickup.longitude}
          data-to-lat={@address.latitude}
          data-to-lng={@address.longitude}
          class="h-48 overflow-hidden rounded-box border border-base-200"
        />

        <div :if={@mine} class="grid grid-cols-2 gap-2">
          <a href={navigator_url(@address)} class="btn btn-outline">
            <.icon name="hero-map" class="size-4" /> {gettext("Navigator")}
          </a>
          <a href={maps_url(@pickup, @address)} target="_blank" rel="noopener" class="btn btn-outline">
            <.icon name="hero-globe-europe-africa" class="size-4" /> {gettext("Yandex Maps")}
          </a>
        </div>
      </div>

      <footer class="border-t border-base-200 p-3">
        <button
          :if={!@mine}
          id={"take-#{@delivery.id}"}
          type="button"
          phx-click="take"
          phx-value-id={@delivery.id}
          class="btn btn-primary btn-lg w-full"
        >
          {gettext("Take")}
        </button>

        <div :if={@mine and @delivery.status == :assigned} class="flex gap-2">
          <button
            id={"refuse-#{@delivery.id}"}
            type="button"
            phx-click="refuse"
            phx-value-id={@delivery.id}
            data-confirm={gettext("Refuse this order?")}
            class="btn btn-ghost btn-lg text-error"
          >
            {gettext("Refuse")}
          </button>
          <button
            id={"pick-up-#{@delivery.id}"}
            type="button"
            phx-click="pick_up"
            phx-value-id={@delivery.id}
            disabled={@order.status != :ready}
            class="btn btn-primary btn-lg flex-1"
          >
            {if @order.status == :ready, do: gettext("Picked up"), else: gettext("Still cooking")}
          </button>
        </div>

        <button
          :if={@mine and @delivery.status == :picked_up}
          id={"hand-over-#{@delivery.id}"}
          type="button"
          phx-click="hand_over"
          phx-value-id={@delivery.id}
          data-confirm={@collect > 0 && gettext("Payment received from the customer?")}
          class="btn btn-success btn-lg w-full"
        >
          {if @collect > 0,
            do: gettext("Delivered, payment received"),
            else: gettext("Handed to the customer")}
        </button>
      </footer>
    </article>
    """
  end

  defp street_line(nil), do: "—"

  defp street_line(address) do
    [address.city, address.street, address.house]
    |> Enum.filter(&present?/1)
    |> Enum.join(", ")
    |> case do
      "" -> address.formatted || "—"
      line -> line
    end
  end

  defp navigator_url(%{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do: "yandexnavi://build_route_on_map?lat_to=#{lat}&lon_to=#{lng}"

  defp navigator_url(address),
    do: "yandexnavi://map_search?" <> URI.encode_query(%{text: street_line(address)})

  defp maps_url(pickup, %{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do:
      "https://yandex.ru/maps/?" <>
        URI.encode_query(%{rtext: "#{point(pickup)}~#{lat},#{lng}", rtt: "auto"})

  defp maps_url(_pickup, address),
    do: "https://yandex.ru/maps/?" <> URI.encode_query(%{text: street_line(address)})

  defp point(%{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do: "#{lat},#{lng}"

  defp point(_pickup), do: ""

  defp located?(%{latitude: lat, longitude: lng}), do: is_float(lat) and is_float(lng)
  defp located?(_address), do: false

  defp present?(value), do: value not in [nil, ""]
end
