defmodule DelivestWeb.KitchenControl do
  use DelivestWeb, :html

  alias Delivest.Oms.Order

  attr :status, :any, default: nil

  def kitchen_indicator(%{status: nil} = assigns), do: ~H""

  def kitchen_indicator(assigns) do
    ~H"""
    <span
      id="kitchen-indicator"
      class={[
        "hidden items-center gap-1.5 rounded-field px-2 py-1 text-xs font-semibold md:flex",
        @status == :online && "bg-success/15 text-success",
        @status != :online && "bg-error text-error-content"
      ]}
    >
      <span class={[
        "size-2 rounded-full",
        if(@status == :online, do: "bg-success", else: "bg-error-content")
      ]} />
      {label(@status)}
    </span>
    """
  end

  attr :orders, :list, default: []

  def kitchen_late_alert(assigns) do
    ~H"""
    <div
      :if={@orders != []}
      id="kitchen-late-orders"
      phx-hook="Alarm"
      data-count={length(@orders)}
      data-tones="523,440,523,440"
      class="fixed bottom-4 right-4 z-40 w-80 rounded-box border border-error bg-base-100 p-4 shadow-xl"
    >
      <h3 class="flex items-center gap-2 font-bold text-error">
        <.icon name="hero-fire" class="size-5" /> {gettext("The kitchen is late")}
      </h3>
      <ul class="mt-2 space-y-1 text-sm">
        <li :for={order <- @orders} id={"kitchen-late-#{order.id}"} class="flex justify-between">
          <span class="font-mono font-bold">#{Order.short_number(order)}</span>
          <span class="tabular-nums text-base-content/70">
            {gettext("due %{time}", time: Calendar.strftime(order.cook_by, "%H:%M"))}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp label(:online), do: gettext("Kitchen online")
  defp label({:offline, nil}), do: gettext("Kitchen offline")

  defp label({:offline, %DateTime{} = since}) do
    minutes = max(0, div(DateTime.diff(DateTime.utc_now(), since), 60))
    gettext("Kitchen offline %{minutes} min", minutes: minutes)
  end
end
