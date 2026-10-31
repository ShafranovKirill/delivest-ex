defmodule DelivestWeb.ChannelCancelAlert do
  use DelivestWeb, :html

  alias Delivest.Oms.Order

  alias Delivest.Integrations.Channels
  alias DelivestWeb.Staff.OrderLive.{CancelReasons, OrderHelpers}

  attr :orders, :list, default: []

  def channel_cancel_alert(assigns) do
    ~H"""
    <div
      :if={@orders != []}
      id="channel-cancelled-orders"
      class="modal modal-open"
      phx-hook="Alarm"
      data-count={length(@orders)}
      data-tones="880,660,440,880,660,440"
    >
      <div class="modal-box max-w-lg border border-error/40">
        <h3 class="flex items-center gap-2 text-lg font-bold text-error">
          <.icon name="hero-bell-alert" class="size-6" />
          {gettext("The aggregator cancelled orders")}
        </h3>
        <p class="pt-1 text-sm text-base-content/70">
          {gettext("Stop cooking and do not hand these orders over. Confirm that you have seen it.")}
        </p>

        <ul class="mt-4 space-y-3">
          <li
            :for={order <- @orders}
            id={"channel-cancelled-#{order.id}"}
            class="space-y-2 rounded-box border border-base-300 p-3"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <span class="font-bold">
                {Channels.name(order.source)} · #{Order.short_number(order)}
              </span>
              <span class="font-mono text-sm">{OrderHelpers.money(order.total_amount)}</span>
            </div>
            <p :if={order.cancel_note || order.cancel_reason} class="text-sm text-error">
              {order.cancel_note || CancelReasons.label(order.cancel_reason)}
            </p>
            <button
              id={"channel-cancelled-ack-#{order.id}"}
              type="button"
              class="btn btn-error btn-sm"
              phx-click="acknowledge_cancel"
              phx-value-id={order.id}
            >
              <.icon name="hero-check" class="size-4" /> {gettext("Got it")}
            </button>
          </li>
        </ul>
      </div>
      <div class="modal-backdrop bg-black/50"></div>
    </div>
    """
  end
end
