defmodule DelivestWeb.Staff.OrderLive.Components.OrderCardComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.{Couriers, Identity, LocalTime}
  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Integrations.{Channels, Crm}
  alias Delivest.Integrations.YandexEda.OrderConfirmation
  alias Delivest.Oms.OrderFlow
  alias DelivestWeb.Staff.OrderLive.{CancelReasons, NextStep, OrderHelpers}
  alias DelivestWeb.Staff.CourierLive.LocationComponents
  alias DelivestWeb.Staff.OrderLive.Components.OrderClock

  attr :id, :string, required: true
  attr :order, :map, required: true
  attr :current_staff, :map, required: true
  attr :current_branch, :map, required: true
  attr :delivery_minutes, :integer, required: true
  attr :couriers, :list, default: []
  attr :positions, :list, default: nil
  attr :pickup, :map, default: nil

  def render_card(assigns) do
    assigns =
      assign(assigns,
        status: assigns.order.status,
        delivery: Couriers.current(assigns.order),
        history: history(assigns.order),
        last: last_transition(assigns.order)
      )

    ~H"""
    <article
      id={@id}
      class={[
        "@container bg-base-100 rounded-box border shadow-sm overflow-hidden transition-colors",
        @status == :created && "border-info ring-2 ring-info/30",
        @status in [:completed, :cancelled] && "border-base-200 opacity-75",
        @status not in [:created, :completed, :cancelled] && "border-base-200"
      ]}
    >
      <header class={[
        "px-3 sm:px-4 py-2.5 border-b border-base-200 flex flex-wrap items-center gap-x-3 gap-y-1.5",
        if(@status == :created, do: "bg-info/10", else: "bg-base-200/40")
      ]}>
        <span :if={@status == :created} class="relative flex size-2.5">
          <span class="absolute inline-flex size-full animate-ping rounded-full bg-info opacity-75" />
          <span class="relative inline-flex size-2.5 rounded-full bg-info" />
        </span>
        <span class="font-mono font-bold text-base text-primary">
          #{Delivest.Oms.Order.short_number(@order)}
        </span>
        <span class="font-mono text-xs text-base-content/50">{@order.number}</span>
        <span class="badge badge-sm badge-ghost gap-1 font-medium">
          <.icon name={fulfillment_icon(@order.fulfillment_type)} class="size-3.5" />
          {OrderHelpers.fulfillment_label(@order.fulfillment_type)}
        </span>
        <span class="text-xs text-base-content/50 tabular-nums">
          {OrderHelpers.local_time(@order.inserted_at)}
        </span>
        <OrderClock.order_clock order={@order} status={@status} delivery_minutes={@delivery_minutes} />
        <OrderClock.kitchen_clock
          :if={@status == :preparing and @last != nil}
          order={@order}
          since={@last.inserted_at}
        />
        <div class="ml-auto text-right leading-tight">
          <p class="font-mono font-bold text-base whitespace-nowrap">
            {OrderHelpers.money(@order.total_amount)}
          </p>
          <p
            :if={@order.discount_amount > 0}
            class="font-mono text-[11px] text-base-content/50 line-through"
          >
            {OrderHelpers.money(@order.subtotal_amount)}
          </p>
          <p
            :if={@order.delivery_amount > 0}
            id={"order-delivery-#{@order.id}"}
            class="text-[11px] text-base-content/60 whitespace-nowrap"
          >
            {gettext("incl. delivery %{amount}", amount: OrderHelpers.money(@order.delivery_amount))}
          </p>
        </div>
      </header>

      <div class="p-3 sm:p-4 grid gap-3 text-sm @3xl:grid-cols-[1fr_1.4fr_1.2fr]">
        <.customer order={@order} current_staff={@current_staff} />
        <.fulfillment
          order={@order}
          can_check_code={
            @status not in [:completed, :cancelled] and
              Identity.can?(@current_staff, "orders.update")
          }
        />
        <.items order={@order} />
      </div>

      <.courier_panel
        :if={@delivery != nil or Couriers.assignable?(@order)}
        order={@order}
        delivery={@delivery}
        couriers={@couriers}
        can_manage={Identity.can?(@current_staff, "orders.update")}
      />

      <.courier_location
        :if={@positions && tracked?(@delivery)}
        order={@order}
        delivery={@delivery}
        positions={@positions}
        pickup={@pickup}
      />

      <p
        :if={@status == :cancelled and @order.cancel_reason}
        id={"order-cancel-reason-#{@order.id}"}
        class="mx-3 sm:mx-4 mb-3 rounded-box bg-error/10 px-3 py-2 text-sm text-error"
      >
        <.icon name="hero-x-circle" class="size-4" />
        {CancelReasons.label(@order.cancel_reason)}<span :if={@order.cancel_note}>: {@order.cancel_note}</span>
      </p>

      <div
        :if={channel_cancel_unseen?(@order, @last)}
        id={"order-channel-cancel-#{@order.id}"}
        class="mx-3 sm:mx-4 mb-3 flex flex-wrap items-center gap-2 rounded-box border border-error/40 bg-error/10 px-3 py-2 text-sm text-error"
      >
        <.icon name="hero-bell-alert" class="size-4" />
        <span class="font-semibold">
          {gettext("Cancelled by %{channel}", channel: Channels.name(@order.source))}
        </span>
        <button
          id={"order-acknowledge-cancel-#{@order.id}"}
          type="button"
          class="btn btn-error btn-xs ml-auto"
          phx-click="acknowledge_cancel"
          phx-value-id={@order.id}
        >
          {gettext("Got it")}
        </button>
      </div>

      <p
        :if={Crm.manual_cancel_required?(@order)}
        id={"order-crm-cancel-#{@order.id}"}
        class="mx-3 sm:mx-4 mb-3 rounded-box bg-error/10 px-3 py-2 text-sm font-semibold text-error"
      >
        <.icon name="hero-exclamation-triangle" class="size-4" />
        {gettext("Cancelled in %{channel}. Cancel order %{number} in %{crm} manually",
          channel: Channels.name(@order.source),
          number: @order.crm.external_number || @order.crm.external_id,
          crm: crm_name(@order)
        )}
      </p>

      <footer class="px-3 sm:px-4 py-2.5 border-t border-base-200 flex flex-wrap items-center gap-2">
        <span
          :if={@order.source != "app"}
          id={"order-source-#{@order.id}"}
          class="badge badge-sm badge-outline"
        >
          {source_label(@order.source)}
        </span>
        <span
          :if={@status == :created and accept_by(@order)}
          id={"order-accept-by-#{@order.id}"}
          class={[
            "badge badge-sm",
            if(overdue?(accept_by(@order)), do: "badge-error", else: "badge-warning")
          ]}
        >
          <.icon name="hero-clock" class="size-3.5" />
          {gettext("Confirm by %{time}", time: OrderHelpers.local_time(accept_by(@order)))}
        </span>
        <.status_control order={@order} current_staff={@current_staff} last={@last} />
        <form
          :if={is_nil(@order.crm) and @order.payment_method != :online}
          id={"order-payment-#{@order.id}"}
          phx-change="update_payment"
          phx-value-order-id={@order.id}
        >
          <select name="payment_method" class="select select-sm select-bordered font-medium">
            <option value="cash" selected={@order.payment_method == :cash}>{gettext("Cash")}</option>
            <option value="card_offline" selected={@order.payment_method == :card_offline}>
              {gettext("Card Offline")}
            </option>
          </select>
        </form>
        <span
          :for={promotion <- @order.promotions}
          class="badge badge-success badge-sm whitespace-nowrap"
          title={promotion.name}
        >
          <.icon name="hero-receipt-percent" class="size-3.5" />
          {promotion.code || promotion.name}
          <span :if={promotion.discount > 0}>−{promotion.discount}</span>
        </span>
        <div class="ml-auto flex items-center gap-1">
          <.link
            :if={is_nil(@order.crm)}
            navigate={~p"/staff/b/#{@current_branch}/orders/#{@order.id}/edit"}
            class="btn btn-ghost btn-sm btn-square"
            title={gettext("Edit Order")}
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
          <button
            type="button"
            phx-click="delete_click"
            phx-value-id={@order.id}
            class="btn btn-ghost btn-sm btn-square text-error hover:bg-error/10"
            title={gettext("Delete Order")}
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
        </div>
      </footer>

      <ol
        :if={@history != []}
        id={"order-history-#{@order.id}"}
        class="px-3 sm:px-4 py-2 border-t border-base-200 flex flex-wrap gap-x-4 gap-y-1 text-xs text-base-content/60"
        aria-label={gettext("Who handled the order")}
      >
        <li
          :for={transition <- @history}
          id={"order-transition-#{transition.id}"}
          class={["flex items-center gap-1", transition.reverted_at && "line-through opacity-60"]}
          title={
            transition.revert_reason &&
              gettext("Reverted: %{reason}", reason: transition.revert_reason)
          }
        >
          <span class={["size-1.5 rounded-full", OrderHelpers.status_dot(transition.to)]} />
          <span class="font-medium text-base-content/80">
            {OrderHelpers.status_label(transition.to)}
          </span>
          <span>{actor_label(@order, transition)}</span>
          <span class="tabular-nums">{OrderHelpers.local_time(transition.inserted_at)}</span>
        </li>
      </ol>
    </article>
    """
  end

  defp fulfillment_icon(:delivery), do: "hero-truck"
  defp fulfillment_icon(:pickup), do: "hero-shopping-bag"
  defp fulfillment_icon(_type), do: "hero-building-storefront"

  attr :order, :map, required: true
  attr :current_staff, :map, required: true

  defp customer(assigns) do
    assigns =
      assign(assigns,
        phone: phone_line(assigns.order),
        tel:
          Enum.join(
            Enum.reject(
              [assigns.order.customer_phone, assigns.order.customer_phone_ext],
              &is_nil/1
            ),
            ","
          ),
        name: assigns.order.customer_name,
        linked?: assigns.order.client_id && Identity.can?(assigns.current_staff, "clients.read")
      )

    ~H"""
    <div class="min-w-0 flex items-start gap-2">
      <.icon name="hero-user" class="size-4 mt-0.5 shrink-0 text-base-content/40" />
      <div :if={@phone || @name} class="min-w-0">
        <a :if={@phone} href={"tel:#{@tel}"} class="font-mono font-semibold hover:text-primary">
          {@phone}
        </a>
        <.link
          :if={@linked?}
          navigate={~p"/staff/clients/#{@order.client_id}"}
          class="block text-base-content/60 truncate hover:text-primary hover:underline"
        >
          {@name || gettext("Open client card")}
        </.link>
        <p :if={!@linked? && @name} class="text-base-content/60 truncate">{@name}</p>
      </div>
      <p :if={!(@phone || @name)} class="text-base-content/50 italic">
        {gettext("Customer not specified")}
      </p>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :can_check_code, :boolean, default: false

  defp fulfillment(assigns) do
    courier = channel_detail(assigns.order, "courier")

    assigns =
      assign(assigns,
        courier: courier_info(courier),
        courier_eta: courier_eta(courier),
        feedback: channel_detail(assigns.order, "feedback")
      )

    ~H"""
    <div class="min-w-0 space-y-1.5">
      <p :if={@order.fulfillment_type == :delivery} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-map-pin" class="size-4 shrink-0 text-base-content/40" />
        <span class="break-words">{OrderHelpers.format_address(@order.address)}</span>
      </p>
      <p
        :if={@courier}
        id={"order-courier-#{@order.id}"}
        class="flex flex-wrap items-center gap-x-1.5 text-base-content/80"
      >
        <.icon name="hero-truck" class="size-4 shrink-0 text-base-content/40" />
        <span>{gettext("Courier")}: {@courier["name"]}</span>
        <a
          :if={@courier["phone"]}
          href={"tel:#{@courier["phone"]}"}
          class="font-mono hover:text-primary"
        >
          {@courier["phone"]}
        </a>
        <span :if={@courier["status"] == "arrived_to_source"} class="badge badge-sm badge-success">
          {gettext("at the restaurant")}
        </span>
        <span
          :if={@courier["status"] != "arrived_to_source" and @courier_eta}
          class="text-base-content/60"
        >
          {gettext("arrives by %{time}", time: OrderHelpers.local_time(@courier_eta))}
        </span>
      </p>
      <form
        :if={@courier != nil and @can_check_code and @order.source == "yandex_eda"}
        id={"order-courier-code-#{@order.id}"}
        phx-submit="courier_code"
        class="flex items-center gap-1.5"
      >
        <input type="hidden" name="order-id" value={@order.id} />
        <input
          type="text"
          name="code"
          inputmode="numeric"
          autocomplete="off"
          placeholder={gettext("Courier code")}
          aria-label={gettext("Courier code")}
          class="input input-xs w-32 font-mono"
        />
        <button type="submit" class="btn btn-xs" phx-disable-with="…">
          {gettext("Check the code")}
        </button>
      </form>
      <p
        :if={@feedback}
        id={"order-feedback-#{@order.id}"}
        class="flex flex-wrap items-center gap-x-1.5 text-base-content/80"
      >
        <.icon name="hero-star-solid" class="size-4 shrink-0 text-warning" />
        <span class="font-medium">{gettext("Review")}: {@feedback["rating"]}/5</span>
        <span
          :for={text <- [@feedback["predefined_comment"], @feedback["comment"]]}
          :if={text not in [nil, ""]}
          class="text-base-content/60 break-words"
        >
          {text}
        </span>
      </p>
      <p :if={@order.cook_by} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-clock" class="size-4 shrink-0 text-base-content/40" />
        {gettext("Prepare by:")} {@order.cook_by
        |> LocalTime.local(@order.branch_id)
        |> Calendar.strftime("%d.%m %H:%M")}
      </p>
      <p
        :if={@order.comment not in [nil, ""]}
        class="flex gap-1.5 rounded-box bg-warning/15 px-2.5 py-1.5 text-base-content"
      >
        <.icon name="hero-chat-bubble-left" class="size-4 shrink-0 text-warning" />
        <span class="break-words">{@order.comment}</span>
      </p>
    </div>
    """
  end

  attr :order, :map, required: true

  defp items(assigns) do
    ~H"""
    <ul class="min-w-0 space-y-1 @3xl:border-l @3xl:border-base-200 @3xl:pl-3">
      <li :for={item <- @order.items} class="flex justify-between gap-2">
        <span class="min-w-0 text-base-content/90">
          <span class="font-mono font-bold">{item.quantity}×</span>
          <.icon :if={item.gift} name="hero-gift" class="size-3.5 text-success" />
          {item.title}
        </span>
        <span class="font-mono text-xs text-base-content/60 shrink-0 pt-0.5">
          {OrderHelpers.money(item.price * item.quantity)}
        </span>
      </li>
    </ul>
    """
  end

  attr :order, :map, required: true
  attr :current_staff, :map, required: true
  attr :last, :map, default: nil

  defp status_control(assigns) do
    %{order: order, current_staff: staff} = assigns

    assigns =
      assign(assigns,
        next: NextStep.for_order(order, staff),
        can_cancel: OrderFlow.can?(order, :cancelled, {:staff, staff}),
        can_revert:
          assigns.last != nil and OrderFlow.can_revert?(staff, order) and
            not Couriers.handed_over?(order)
      )

    ~H"""
    <span
      id={"order-status-#{@order.id}"}
      class={["badge badge-sm border font-medium", OrderHelpers.status_color(@order.status)]}
    >
      {OrderHelpers.status_label(@order.status)}
    </span>
    <.crm_state :if={@order.crm} order={@order} />
    <button
      :if={@next}
      type="button"
      id={"order-next-#{@order.id}"}
      class="btn btn-sm btn-primary"
      phx-click="advance"
      phx-value-order-id={@order.id}
      phx-value-to={elem(@next, 0)}
    >
      <.icon name="hero-arrow-right-circle" class="size-4" /> {elem(@next, 1)}
    </button>
    <button
      :if={@can_cancel}
      type="button"
      id={"order-cancel-#{@order.id}"}
      class="btn btn-sm btn-ghost text-error hover:bg-error/10"
      phx-click="cancel_click"
      phx-value-order-id={@order.id}
    >
      <.icon name="hero-x-circle" class="size-4" /> {gettext("Cancel")}
    </button>
    <button
      :if={@can_revert}
      type="button"
      id={"order-revert-#{@order.id}"}
      class="btn btn-sm btn-ghost btn-square"
      phx-click="revert_click"
      phx-value-order-id={@order.id}
      title={gettext("Revert to «%{status}»", status: OrderHelpers.status_label(@last.from))}
    >
      <.icon name="hero-arrow-uturn-left" class="size-4" />
    </button>
    """
  end

  attr :order, :map, required: true
  attr :delivery, :map, default: nil
  attr :couriers, :list, default: []
  attr :can_manage, :boolean, default: false

  defp courier_panel(assigns) do
    assigns =
      assign(assigns,
        assignable: assigns.can_manage and Couriers.assignable?(assigns.order),
        courier_id: assigns.delivery && assigns.delivery.courier_id
      )

    ~H"""
    <div
      id={"order-delivery-panel-#{@order.id}"}
      class="mx-3 sm:mx-4 mb-3 flex flex-wrap items-center gap-2 rounded-box border border-base-200 bg-base-200/40 px-3 py-2 text-sm"
    >
      <.icon name="hero-truck" class="size-4 text-base-content/50" />
      <span
        id={"order-delivery-state-#{@order.id}"}
        class={["badge badge-sm font-medium", delivery_badge(@delivery)]}
      >
        {delivery_label(@delivery)}
      </span>
      <span :if={@delivery && @delivery.courier} class="font-medium">
        {@delivery.courier.name || @delivery.courier.login}
      </span>
      <.yandex_courier :if={@delivery && @delivery.provider == :yandex} delivery={@delivery} />
      <span
        :if={is_nil(@delivery) and provider_failed?(@order)}
        id={"order-delivery-failed-#{@order.id}"}
        class="text-xs text-error"
      >
        {gettext("Yandex Delivery did not take the last request")}
      </span>
      <div :if={@assignable} class="ml-auto flex flex-wrap items-center gap-2">
        <button
          :if={is_nil(@delivery)}
          type="button"
          id={"order-find-courier-#{@order.id}"}
          class="btn btn-xs btn-primary"
          phx-click="find_courier"
          phx-value-order-id={@order.id}
        >
          <.icon name="hero-magnifying-glass" class="size-3.5" /> {gettext("Find a courier")}
        </button>
        <form
          :if={@couriers != [] and (is_nil(@delivery) or @delivery.status != :picked_up)}
          id={"order-assign-courier-#{@order.id}"}
          phx-change="assign_courier"
          phx-value-order-id={@order.id}
        >
          <select
            name="courier_id"
            class="select select-xs select-bordered"
            aria-label={gettext("Assign a courier")}
          >
            <option value="" disabled selected={is_nil(@courier_id)}>
              {gettext("Assign a courier")}
            </option>
            <option
              :for={courier <- @couriers}
              value={courier.id}
              selected={courier.id == @courier_id}
            >
              {courier.name || courier.login}
            </option>
          </select>
        </form>
        <button
          :if={@delivery && @delivery.status == :assigned}
          type="button"
          id={"order-unassign-courier-#{@order.id}"}
          class="btn btn-xs btn-ghost text-error hover:bg-error/10"
          phx-click="unassign_courier"
          phx-value-order-id={@order.id}
        >
          {gettext("Remove the courier")}
        </button>
      </div>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :delivery, :map, required: true
  attr :positions, :list, required: true
  attr :pickup, :map, default: nil

  defp courier_location(assigns) do
    assigns =
      assign(assigns,
        position: Enum.find(assigns.positions, &(&1.id == assigns.delivery.courier_id))
      )

    ~H"""
    <div id={"order-courier-location-#{@order.id}"} class="mx-3 sm:mx-4 mb-3 space-y-1">
      <p :if={is_nil(@position)} class="text-xs text-base-content/60">
        {gettext(
          "The courier location is not known: the courier page is closed or the location is off"
        )}
      </p>
      <LocationComponents.location_age :if={@position} at={@position.at} />
      <LocationComponents.couriers_map
        :if={@position}
        id={"order-courier-map-#{@order.id}"}
        from={@pickup}
        to={located(@order.address)}
        positions={[@position]}
        courier_id={@delivery.courier_id}
        class="h-56"
      />
    </div>
    """
  end

  defp tracked?(%{provider: :staff, status: status}), do: status in [:assigned, :picked_up]
  defp tracked?(_delivery), do: false

  defp located(%{latitude: lat, longitude: lng} = address) when is_float(lat) and is_float(lng),
    do: address

  defp located(_address), do: nil

  attr :delivery, :map, required: true

  defp yandex_courier(assigns) do
    assigns =
      assign(assigns,
        details: assigns.delivery.details || %{},
        returning: YandexDelivery.returning?(assigns.delivery)
      )

    ~H"""
    <span class="badge badge-sm badge-ghost">{gettext("Yandex")}</span>
    <span :if={@details["performer"]} id={"order-yandex-courier-#{@delivery.order_id}"}>
      <span class="font-medium">{@details["performer"]["name"]}</span>
      <span :if={@details["performer"]["car"]} class="text-base-content/60">
        · {@details["performer"]["car"]}
      </span>
    </span>
    <a
      :if={@details["phone"]}
      href={"tel:#{@details["phone"]}"}
      class="link link-hover inline-flex items-center gap-1"
    >
      <.icon name="hero-phone" class="size-3.5" /> {courier_phone(@details["phone"])}
    </a>
    <span :if={@details["price"]} class="text-base-content/60">
      {@details["price"]} ₽
    </span>
    <a
      :if={@details["tracking_url"]}
      href={@details["tracking_url"]}
      target="_blank"
      rel="noopener"
      class="link link-primary"
    >
      {gettext("Tracking")}
    </a>
    <span
      :if={@returning}
      id={"order-yandex-returning-#{@delivery.order_id}"}
      class="badge badge-sm badge-error"
    >
      {gettext("The courier is bringing the order back")}
    </span>
    """
  end

  defp courier_phone(phone) do
    case String.split(phone, ",,", parts: 2) do
      [number, ext] -> gettext("%{number} ext. %{ext}", number: number, ext: ext)
      [number] -> number
    end
  end

  defp provider_failed?(%{deliveries: deliveries}) when is_list(deliveries),
    do: match?(%{provider: :yandex, close_reason: :provider_error}, List.last(deliveries))

  defp provider_failed?(_order), do: false

  defp delivery_label(nil), do: gettext("No courier yet")

  defp delivery_label(%{status: :searching, provider: :yandex}),
    do: gettext("Looking for a Yandex courier")

  defp delivery_label(%{status: :searching}), do: gettext("Looking for a courier")
  defp delivery_label(%{status: :assigned}), do: gettext("Courier assigned")
  defp delivery_label(%{status: :picked_up}), do: gettext("Courier is on the way")

  defp delivery_badge(nil), do: "badge-ghost"
  defp delivery_badge(%{status: :searching}), do: "badge-warning"
  defp delivery_badge(%{status: :assigned}), do: "badge-info"
  defp delivery_badge(%{status: :picked_up}), do: "badge-success"

  attr :order, :map, required: true

  defp crm_state(assigns) do
    ~H"""
    <span class="text-xs text-base-content/60">
      CRM:
      <%= case @order.crm.status do %>
        <% "sent" -> %>
          <span :if={@order.crm.external_number} class="font-mono font-bold">
            #{@order.crm.external_number}
          </span>
        <% "failed" -> %>
          <span class="text-error font-bold uppercase">{gettext("error")}</span>
        <% status -> %>
          {status || gettext("sending")}
      <% end %>
    </span>
    <span
      :if={unmapped_crm_code(@order)}
      id={"order-unmapped-#{@order.id}"}
      class="badge badge-warning badge-sm"
      title={gettext("Set this code in the branch %{crm} settings", crm: crm_name(@order))}
    >
      {gettext("%{crm} status %{code} is not mapped",
        crm: crm_name(@order),
        code: unmapped_crm_code(@order)
      )}
    </span>
    """
  end

  defp history(%{transitions: transitions}) when is_list(transitions), do: transitions
  defp history(_order), do: []

  defp last_transition(order) do
    order
    |> history()
    |> Enum.reject(& &1.reverted_at)
    |> List.last()
    |> case do
      %{to: to} = transition when to == order.status -> transition
      _other -> nil
    end
  end

  defp channel_cancel_unseen?(%{status: :cancelled, cancel_acknowledged_at: nil}, %{
         source: :channel
       }),
       do: true

  defp channel_cancel_unseen?(_order, _last), do: false

  defp actor_label(_order, %{staff: %{} = staff}), do: staff.name || staff.login
  defp actor_label(order, %{source: :crm}), do: crm_name(order)
  defp actor_label(order, %{source: :channel}), do: Channels.name(order.source)
  defp actor_label(_order, %{source: :courier}), do: gettext("Courier")
  defp actor_label(_order, %{source: :delivery}), do: gettext("Yandex Delivery")
  defp actor_label(_order, %{source: :system}), do: gettext("System")
  defp actor_label(_order, _transition), do: "—"

  defp unmapped_crm_code(%{crm: %{remote_status: nil, remote_status_code: code}})
       when is_binary(code),
       do: code

  defp unmapped_crm_code(_order), do: nil

  defp phone_line(%{customer_phone: phone, customer_phone_ext: ext})
       when is_binary(phone) and is_binary(ext),
       do: gettext("%{number} ext. %{ext}", number: phone, ext: ext)

  defp phone_line(%{customer_phone: phone}), do: phone

  defp channel_detail(%{channel: %{details: details}}, key) when is_map(details), do: details[key]
  defp channel_detail(_order, _key), do: nil

  defp accept_by(order), do: OrderConfirmation.accept_by(order)

  defp courier_info(%{"courier" => %{"name" => name} = courier}) when is_binary(name),
    do: courier

  defp courier_info(_courier), do: nil

  defp courier_eta(%{"maxPlaceArrivalTime" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp courier_eta(_courier), do: nil

  defp overdue?(datetime), do: DateTime.compare(datetime, DateTime.utc_now()) == :lt

  defp source_label("staff"), do: gettext("Admin")
  defp source_label(source), do: Channels.name(source)

  defp crm_name(%{crm: %{provider: provider}}) do
    case Crm.provider_name(provider) do
      {:error, _reason} -> provider
      name -> name
    end
  end

  defp crm_name(_order), do: "CRM"
end
