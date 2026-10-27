defmodule DelivestWeb.Staff.OrderLive.Components.OrderCardComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Identity
  alias Delivest.Integrations.{Channels, Crm}
  alias Delivest.Oms.OrderStatus
  alias DelivestWeb.Staff.OrderLive.{CancelReasons, NextStep, OrderHelpers}
  alias DelivestWeb.Staff.OrderLive.Components.OrderClock

  attr :id, :string, required: true
  attr :order, :map, required: true
  attr :current_staff, :map, required: true
  attr :delivery_minutes, :integer, required: true

  def render_card(assigns) do
    assigns = assign(assigns, status: OrderStatus.current(assigns.order))

    ~H"""
    <article
      id={@id}
      class={[
        "bg-base-100 rounded-box border shadow-sm overflow-hidden transition-colors",
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
        <span class="font-mono font-bold text-base text-primary">#{@order.number}</span>
        <span class="badge badge-sm badge-ghost gap-1 font-medium">
          <.icon name={fulfillment_icon(@order.fulfillment_type)} class="size-3.5" />
          {OrderHelpers.fulfillment_label(@order.fulfillment_type)}
        </span>
        <span class="text-xs text-base-content/50 tabular-nums">
          {OrderHelpers.local_time(@order.inserted_at)}
        </span>
        <OrderClock.order_clock order={@order} status={@status} delivery_minutes={@delivery_minutes} />
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
        </div>
      </header>

      <div class="p-3 sm:p-4 grid gap-3 text-sm lg:grid-cols-[1fr_1.4fr_1.2fr]">
        <.customer order={@order} current_staff={@current_staff} />
        <.fulfillment order={@order} />
        <.items order={@order} />
      </div>

      <p
        :if={@status == :cancelled and @order.cancel_reason}
        id={"order-cancel-reason-#{@order.id}"}
        class="mx-3 sm:mx-4 mb-3 rounded-box bg-error/10 px-3 py-2 text-sm text-error"
      >
        <.icon name="hero-x-circle" class="size-4" />
        {CancelReasons.label(@order.cancel_reason)}<span :if={@order.cancel_note}>: {@order.cancel_note}</span>
      </p>

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
        <.status_control order={@order} />
        <form
          :if={@order.status != :crm}
          id={"order-payment-#{@order.id}"}
          phx-change="update_order"
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
            :if={@order.status != :crm}
            navigate={~p"/staff/orders/#{@order.id}/edit"}
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
        phone:
          (assigns.order.client && assigns.order.client.phone) || assigns.order.customer_phone,
        name: (assigns.order.client && assigns.order.client.name) || assigns.order.customer_name,
        linked?: assigns.order.client_id && Identity.can?(assigns.current_staff, "clients.read")
      )

    ~H"""
    <div class="min-w-0 flex items-start gap-2">
      <.icon name="hero-user" class="size-4 mt-0.5 shrink-0 text-base-content/40" />
      <div :if={@phone || @name} class="min-w-0">
        <a :if={@phone} href={"tel:#{@phone}"} class="font-mono font-semibold hover:text-primary">
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

  defp fulfillment(assigns) do
    ~H"""
    <div class="min-w-0 space-y-1.5">
      <p :if={@order.fulfillment_type == :delivery} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-map-pin" class="size-4 shrink-0 text-base-content/40" />
        <span class="break-words">{OrderHelpers.format_address(@order.address)}</span>
      </p>
      <p :if={@order.cook_by} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-clock" class="size-4 shrink-0 text-base-content/40" />
        {gettext("Prepare by:")} {Calendar.strftime(@order.cook_by, "%d.%m %H:%M")}
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
    <ul class="min-w-0 space-y-1 lg:border-l lg:border-base-200 lg:pl-3">
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

  defp status_control(%{order: %{status: :crm}} = assigns) do
    ~H"""
    <span class={["badge badge-sm border", OrderHelpers.status_color(OrderStatus.current(@order))]}>
      {OrderHelpers.status_label(OrderStatus.current(@order))}
    </span>
    <span class="text-xs text-base-content/60">
      CRM:
      <%= case @order.crm && @order.crm.status do %>
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

  defp status_control(assigns) do
    assigns = assign(assigns, next: NextStep.for_order(assigns.order))

    ~H"""
    <button
      :if={@next}
      type="button"
      id={"order-next-#{@order.id}"}
      class="btn btn-sm btn-primary"
      phx-click="update_order"
      phx-value-order-id={@order.id}
      phx-value-status={elem(@next, 0)}
    >
      <.icon name="hero-arrow-right-circle" class="size-4" /> {elem(@next, 1)}
    </button>
    <form id={"order-status-#{@order.id}"} phx-change="update_order" phx-value-order-id={@order.id}>
      <select
        name="status"
        class={["select select-sm font-medium border", OrderHelpers.status_color(@order.status)]}
      >
        <option
          :for={status <- Delivest.Oms.Order.statuses_for(@order.fulfillment_type)}
          value={status}
          selected={@order.status == status}
          class="bg-base-100 text-base-content"
        >
          {OrderHelpers.status_label(status)}
        </option>
      </select>
    </form>
    """
  end

  defp unmapped_crm_code(%{crm: %{remote_status: nil, remote_status_code: code}})
       when is_binary(code),
       do: code

  defp unmapped_crm_code(_order), do: nil

  defp source_label("staff"), do: gettext("Admin")
  defp source_label(source), do: Channels.name(source)

  defp crm_name(%{crm: %{provider: provider}}) do
    case Crm.provider_name(provider) do
      {:error, _reason} -> provider
      name -> name
    end
  end
end
