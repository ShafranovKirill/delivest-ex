defmodule DelivestWeb.Staff.OrderLive.Components.FooterComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :cart, :map, required: true
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

      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="switch_tab"
          phx-value-tab="cart"
          class="btn btn-outline btn-square lg:hidden"
          aria-label={gettext("Back")}
        >
          <.icon name="hero-arrow-left" class="size-4" />
        </button>
        <button
          type="submit"
          form="order-details-form"
          disabled={@cart.items == []}
          class="btn btn-primary flex-1 justify-between h-12"
        >
          <span class="flex items-center gap-1.5">
            <.icon name="hero-check" class="size-5" />
            {if @is_edit, do: gettext("Save Changes"), else: gettext("Submit Order")}
          </span>
          <span class="font-mono text-base">{OrderHelpers.money(@cart.total_amount)}</span>
        </button>
      </div>
    </div>
    """
  end
end
