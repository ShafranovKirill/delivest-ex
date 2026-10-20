defmodule DelivestWeb.Staff.OrderLive.Components.CartComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  attr :cart, :map, required: true

  def render_items(assigns) do
    ~H"""
    <div
      :if={@cart.items == []}
      class="h-64 flex flex-col items-center justify-center text-base-content/40 space-y-2"
    >
      <.icon name="hero-shopping-cart" class="size-12 stroke-1" />
      <p class="text-sm font-medium">{gettext("Cart is empty")}</p>
    </div>

    <div :if={@cart.items != []}>
      <div class="flex justify-between items-center mb-3 pb-2 border-b border-base-200">
        <span class="text-xs font-bold uppercase text-base-content/60">
          {gettext("Items in Cart")}
        </span>
        <button
          type="button"
          phx-click="detach_cart"
          class="btn btn-ghost btn-xs text-error hover:bg-error/10"
        >
          <.icon name="hero-trash" class="size-3.5 mr-1" />
          {gettext("Clear Cart")}
        </button>
      </div>

      <div class="space-y-2">
        <div
          :for={item <- @cart.items}
          class="flex items-center justify-between p-2.5 rounded-box bg-base-200/60 border border-base-200"
        >
          <div class="flex-1 min-w-0 pr-2">
            <p class="font-medium text-xs sm:text-sm truncate">{item.name}</p>
            <p class="text-xs text-base-content/60 font-mono mt-0.5">
              {item.price} × {item.quantity} =
              <span class="font-bold text-base-content">{item.total_price} ₽</span>
            </p>
          </div>

          <div class="flex items-center gap-1 shrink-0">
            <button
              type="button"
              phx-click="remove_item"
              phx-value-product-id={item.product_id}
              class="btn btn-xs btn-square btn-ghost"
            >
              <.icon name="hero-minus" class="size-3" />
            </button>
            <span class="w-5 text-center text-xs font-bold font-mono">{item.quantity}</span>
            <button
              type="button"
              phx-click="add_item"
              phx-value-product-id={item.product_id}
              class="btn btn-xs btn-square btn-ghost"
            >
              <.icon name="hero-plus" class="size-3" />
            </button>
            <button
              type="button"
              phx-click="delete_item"
              phx-value-product-id={item.product_id}
              class="btn btn-xs btn-square btn-ghost text-error"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :cart, :map, required: true

  def render_summary(assigns) do
    ~H"""
    <div class="lg:hidden mb-4 p-3 rounded-box bg-base-200/70 border border-base-300">
      <div class="flex justify-between items-center mb-2 pb-2 border-b border-base-300">
        <span class="font-bold text-xs uppercase text-base-content/60">
          {gettext("Selected Items")} ({@cart.total_quantity})
        </span>
        <button
          type="button"
          phx-click="switch_tab"
          phx-value-tab="cart"
          class="btn btn-ghost btn-xs text-primary"
        >
          {gettext("Edit")}
        </button>
      </div>
      <div class="space-y-1.5 max-h-36 overflow-y-auto">
        <div :for={item <- @cart.items} class="flex justify-between text-xs">
          <span class="truncate pr-2">{item.name} × {item.quantity}</span>
          <span class="font-mono font-bold shrink-0">{item.total_price} ₽</span>
        </div>
      </div>
    </div>
    """
  end
end
