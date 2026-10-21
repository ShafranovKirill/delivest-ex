defmodule DelivestWeb.Staff.OrderLive.Components.FooterComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :cart, :map, required: true
  attr :active_tab, :atom, required: true
  attr :is_edit, :boolean, required: true

  def render_footer(assigns) do
    ~H"""
    <div class="p-3 lg:p-4 border-t border-base-200 bg-base-100 shrink-0 space-y-2">
      <div :if={@cart.discount_amount > 0} class="flex justify-between text-sm text-base-content/60">
        <span>{gettext("Without discount")}</span>
        <span class="font-mono line-through">{OrderHelpers.money(@cart.subtotal_amount)}</span>
      </div>
      <div :if={@cart.discount_amount > 0} class="flex justify-between text-sm text-success">
        <span>{gettext("Discount")}</span>
        <span class="font-mono">−{OrderHelpers.money(@cart.discount_amount)}</span>
      </div>
      <div class="flex justify-between items-center text-base lg:text-lg font-bold">
        <span>{gettext("Total:")}</span>
        <span class="font-mono text-lg lg:text-xl">{OrderHelpers.money(@cart.total_amount)}</span>
      </div>

      <button
        :if={@active_tab == :cart}
        type="button"
        phx-click="switch_tab"
        phx-value-tab="details"
        disabled={@cart.items == []}
        class="btn btn-primary w-full"
      >
        {gettext("Proceed to Checkout")}
        <.icon name="hero-arrow-right" class="size-4 ml-1" />
      </button>

      <div :if={@active_tab == :details} class="flex gap-2">
        <button
          type="button"
          phx-click="switch_tab"
          phx-value-tab="cart"
          class="btn btn-outline lg:hidden"
        >
          <.icon name="hero-arrow-left" class="size-4" />
          {gettext("Back")}
        </button>
        <button
          type="submit"
          form="order-details-form"
          disabled={@cart.items == []}
          class="btn btn-success flex-1 text-white"
        >
          <.icon name="hero-check" class="size-5 mr-1" />
          {if @is_edit, do: gettext("Save Changes"), else: gettext("Submit Order")}
        </button>
      </div>
    </div>
    """
  end
end
