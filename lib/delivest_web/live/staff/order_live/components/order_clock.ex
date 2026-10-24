defmodule DelivestWeb.Staff.OrderLive.Components.OrderClock do
  use DelivestWeb, :html

  alias Delivest.Oms.OrderDeadline
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :order, :map, required: true
  attr :status, :atom, required: true
  attr :delivery_minutes, :integer, required: true

  def order_clock(%{status: :created} = assigns) do
    ~H"""
    <span
      id={"order-clock-#{@order.id}"}
      phx-hook=".OrderClock"
      data-mode="waiting"
      data-at={DateTime.to_iso8601(@order.inserted_at)}
      data-text={gettext("waiting %{minutes} min")}
      class={clock_class()}
    ></span>
    """
  end

  def order_clock(%{status: status} = assigns) when status in [:preparing, :ready, :delivering] do
    deadline = OrderDeadline.at(assigns.order, assigns.delivery_minutes)
    assigns = assign(assigns, deadline: deadline)

    ~H"""
    <span class="text-xs text-base-content/60 tabular-nums">
      {gettext("due %{time}", time: OrderHelpers.local_time(@deadline))}
    </span>
    <span
      id={"order-clock-#{@order.id}"}
      phx-hook=".OrderClock"
      data-mode="deadline"
      data-at={DateTime.to_iso8601(@deadline)}
      data-text={gettext("%{minutes} min left")}
      data-late-text={gettext("%{minutes} min late")}
      class={clock_class()}
    ></span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".OrderClock">
      export default {
        mounted() {
          this.tick()
          this.timer = setInterval(() => this.tick(), 15000)
        },
        updated() {
          this.tick()
        },
        destroyed() {
          clearInterval(this.timer)
        },
        tick() {
          const { mode, at, text, lateText } = this.el.dataset
          const minutes = Math.round((Date.parse(at) - Date.now()) / 60000)

          if (mode === "waiting") {
            const waited = Math.max(0, -minutes)
            this.el.dataset.tone = waited >= 7 ? "late" : waited >= 3 ? "warn" : "ok"
            this.el.textContent = text.replace("%{minutes}", waited)
          } else {
            this.el.dataset.tone = minutes < 0 ? "late" : minutes <= 10 ? "warn" : "ok"
            this.el.textContent = (minutes < 0 ? lateText : text).replace("%{minutes}", Math.abs(minutes))
          }
        }
      }
    </script>
    """
  end

  def order_clock(assigns), do: ~H""

  defp clock_class do
    "badge badge-sm font-semibold tabular-nums border-0 " <>
      "data-[tone=ok]:bg-success/15 data-[tone=ok]:text-success " <>
      "data-[tone=warn]:bg-warning data-[tone=warn]:text-warning-content " <>
      "data-[tone=late]:bg-error data-[tone=late]:text-error-content"
  end
end
