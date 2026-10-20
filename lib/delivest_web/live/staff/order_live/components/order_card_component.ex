defmodule DelivestWeb.Staff.OrderLive.Components.OrderCardComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Identity
  alias Delivest.Oms.OrderStatus
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :id, :string, required: true
  attr :order, :map, required: true
  attr :current_staff, :map, required: true

  def render_card(assigns) do
    ~H"""
    <article id={@id} class="bg-base-100 rounded-box border border-base-200 shadow-sm overflow-hidden">
      <header class="px-3 sm:px-4 py-2.5 bg-base-200/40 border-b border-base-200 flex items-center gap-3">
        <span class="font-mono font-bold text-base text-primary">#{@order.number}</span>
        <span class="text-xs text-base-content/50 tabular-nums">
          {OrderHelpers.local_datetime(@order.inserted_at)}
        </span>
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

      <div class="p-3 sm:p-4 grid gap-3 text-sm lg:grid-cols-[1fr_1.4fr_1fr]">
        <.customer order={@order} current_staff={@current_staff} />
        <.fulfillment order={@order} />
        <.items order={@order} />
      </div>

      <footer class="px-3 sm:px-4 py-2.5 border-t border-base-200 flex flex-wrap items-center gap-2">
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
    <div class="min-w-0 space-y-1">
      <span class="badge badge-sm badge-ghost font-medium uppercase">
        {OrderHelpers.fulfillment_label(@order.fulfillment_type)}
      </span>
      <p :if={@order.fulfillment_type == :delivery} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-map-pin" class="size-4 shrink-0 text-base-content/40" />
        <span class="break-words">{OrderHelpers.format_address(@order.address)}</span>
      </p>
      <p :if={@order.cook_by} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-clock" class="size-4 shrink-0 text-base-content/40" />
        {gettext("Prepare by:")} {Calendar.strftime(@order.cook_by, "%d.%m %H:%M")}
      </p>
      <p :if={@order.comment not in [nil, ""]} class="flex gap-1.5 text-base-content/80">
        <.icon name="hero-chat-bubble-left" class="size-4 shrink-0 text-base-content/40" />
        <span class="break-words">{@order.comment}</span>
      </p>
    </div>
    """
  end

  attr :order, :map, required: true

  defp items(assigns) do
    ~H"""
    <details class="group min-w-0">
      <summary class="cursor-pointer select-none text-primary font-medium flex items-center gap-1 list-none">
        <.icon name="hero-shopping-bag" class="size-4" />
        {ngettext("%{count} item", "%{count} items", length(@order.items))}
        <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
      </summary>
      <ul class="mt-2 space-y-1 pt-2 border-t border-base-200">
        <li :for={item <- @order.items} class="flex justify-between gap-2 text-xs">
          <span class="truncate text-base-content/80">
            <.icon :if={item.gift} name="hero-gift" class="size-3 text-success" />
            {item.title} × {item.quantity}
          </span>
          <span class="font-mono shrink-0">{OrderHelpers.money(item.price * item.quantity)}</span>
        </li>
      </ul>
    </details>
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
    """
  end

  defp status_control(assigns) do
    ~H"""
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
end
