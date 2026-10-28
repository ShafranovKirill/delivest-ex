defmodule DelivestWeb.Staff.OrderLive.Components.CartComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  alias DelivestWeb.Staff.PromotionLive.ReasonText

  attr :cart, :map, required: true

  def render_items(assigns) do
    ~H"""
    <.empty_state
      :if={@cart.items == []}
      icon="hero-shopping-cart"
      title={gettext("Cart is empty")}
      class="h-64"
    />

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
          id={"cart-item-#{item_key(item)}"}
          class={[
            "flex items-center justify-between p-2.5 rounded-box border",
            if(gift?(item),
              do: "bg-success/10 border-success/30",
              else: "bg-base-200/60 border-base-200"
            )
          ]}
        >
          <div class="flex-1 min-w-0 pr-2">
            <p class="font-medium text-xs sm:text-sm truncate">
              <.icon :if={gift?(item)} name="hero-gift" class="size-4 text-success" />
              {item.name}
            </p>
            <p :if={gift?(item)} class="text-xs text-success font-medium mt-0.5">
              {gettext("Gift × %{count}", count: item.quantity)}
            </p>
            <p :if={!gift?(item)} class="text-xs text-base-content/60 font-mono mt-0.5">
              {item.price} × {item.quantity} =
              <span :if={discounted?(item)} class="line-through opacity-60">{base_total(item)}</span>
              <span class="font-bold text-base-content">{OrderHelpers.money(item.total_price)}</span>
            </p>
          </div>

          <div :if={!gift?(item)} class="flex items-center gap-1 shrink-0">
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

  attr :id, :string, required: true
  attr :cart, :map, required: true

  def render_promo(assigns) do
    ~H"""
    <div :if={@cart.items != []} id={@id} class="my-4 space-y-2">
      <.form
        :if={is_nil(@cart.promo_code)}
        for={%{}}
        as={:promo}
        id={"#{@id}-form"}
        phx-submit="apply_promo"
        class="join w-full"
      >
        <input
          type="text"
          name="promo[code]"
          placeholder={gettext("Promo code")}
          maxlength="32"
          autocomplete="off"
          class="input input-sm join-item w-full font-mono uppercase"
        />
        <button type="submit" class="btn btn-sm btn-primary join-item">{gettext("Apply")}</button>
      </.form>

      <div
        :if={@cart.code}
        class={[
          "rounded-box border p-2.5 text-xs flex items-start gap-2",
          code_class(@cart.code.status)
        ]}
      >
        <.icon name="hero-ticket" class="size-4 shrink-0 mt-0.5" />
        <div class="flex-1 min-w-0">
          <p class="font-bold font-mono">{@cart.code.code}</p>
          <p :if={@cart.code.name}>{@cart.code.name}</p>
          <p :if={@cart.code.status == :rejected}>{ReasonText.rejected(@cart.code.reason)}</p>
          <p :if={@cart.code.status == :pending}>
            {Enum.map_join(@cart.code.reasons, "; ", &ReasonText.unmet/1)}
          </p>
        </div>
        <button type="button" phx-click="remove_promo" class="btn btn-ghost btn-xs btn-square">
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <div :for={promotion <- @cart.promotions} class="flex justify-between text-xs text-success">
        <span class="truncate">
          <.icon name="hero-receipt-percent" class="size-3.5" /> {promotion.name}
        </span>
        <span :if={promotion.discount > 0} class="font-mono font-bold">−{OrderHelpers.money(
          promotion.discount
        )}</span>
      </div>

      <div :for={hint <- @cart.hints} class="text-xs text-base-content/60">
        <.icon name="hero-light-bulb" class="size-3.5" />
        <span class="font-medium">{hint.name}</span>: {Enum.map_join(
          hint.reasons,
          "; ",
          &ReasonText.unmet/1
        )}
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
          <span class="truncate pr-2">
            <.icon :if={gift?(item)} name="hero-gift" class="size-3.5 text-success" />
            {item.name} × {item.quantity}
          </span>
          <span class="font-mono font-bold shrink-0">{OrderHelpers.money(item.total_price)}</span>
        </div>
      </div>
    </div>
    """
  end

  defp gift?(item), do: Map.get(item, :gift, false)

  defp item_key(item), do: item |> Map.get(:key, item.product_id) |> String.replace(":", "-")

  defp base_total(item), do: Map.get(item, :base_total, item.total_price)

  defp discounted?(item), do: base_total(item) > item.total_price

  defp code_class(:applied), do: "border-success/40 bg-success/10 text-success"
  defp code_class(:pending), do: "border-warning/40 bg-warning/10"
  defp code_class(:rejected), do: "border-error/40 bg-error/10 text-error"
end
