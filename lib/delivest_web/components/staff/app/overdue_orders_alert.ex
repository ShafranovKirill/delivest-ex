defmodule DelivestWeb.OverdueOrdersAlert do
  use DelivestWeb, :html

  alias Delivest.Integrations.Channels
  alias Delivest.Integrations.YandexEda.OrderConfirmation
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :orders, :list, default: []

  def overdue_orders_alert(assigns) do
    ~H"""
    <div
      :if={@orders != []}
      id="overdue-orders"
      class="modal modal-open"
      phx-hook="Alarm"
      data-count={length(@orders)}
    >
      <div class="modal-box max-w-lg border border-error/40">
        <h3 class="flex items-center gap-2 text-lg font-bold text-error">
          <.icon name="hero-bell-alert" class="size-6" />
          {gettext("Orders are not confirmed in time")}
        </h3>
        <p class="pt-1 text-sm text-base-content/70">
          {gettext(
            "The aggregator is waiting. Confirm the order, cancel it or leave it as it is, it stays among new orders."
          )}
        </p>

        <ul class="mt-4 space-y-3">
          <li
            :for={order <- @orders}
            id={"overdue-order-#{order.id}"}
            class="space-y-3 rounded-box border border-base-300 p-3"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <span class="font-bold">
                {Channels.name(order.source)} · #{order.channel.external_number || order.number}
              </span>
              <span class="font-mono text-sm">{OrderHelpers.money(order.total_amount)}</span>
            </div>
            <p class="text-sm text-error">
              {gettext("Had to be confirmed by %{time}",
                time: OrderHelpers.local_time(OrderConfirmation.accept_by(order))
              )}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                id={"overdue-confirm-#{order.id}"}
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="overdue_confirm"
                phx-value-id={order.id}
              >
                <.icon name="hero-check" class="size-4" /> {gettext("Confirm")}
              </button>
              <button
                id={"overdue-cancel-#{order.id}"}
                type="button"
                class="btn btn-error btn-outline btn-sm"
                phx-click="overdue_cancel"
                phx-value-id={order.id}
                data-confirm={gettext("Cancel the order? The aggregator will see it cancelled.")}
              >
                <.icon name="hero-x-mark" class="size-4" /> {gettext("Cancel order")}
              </button>
              <button
                id={"overdue-keep-#{order.id}"}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="overdue_keep"
                phx-value-id={order.id}
              >
                {gettext("Let it wait")}
              </button>
            </div>
          </li>
        </ul>
      </div>
      <div class="modal-backdrop bg-black/50"></div>
    </div>
    """
  end
end
