defmodule DelivestWeb.Staff.OrderLive.Components.CatalogComponent do
  use DelivestWeb, :html

  def render_catalog(assigns) do
    ~H"""
    <div>
      <div class="p-3 border-b border-base-200 space-y-2 shrink-0 bg-base-100">
        <form phx-change="search_products" phx-submit="search_products" class="relative w-full">
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-2.5 size-4 text-base-content/40"
          />
          <input
            type="text"
            name="search[query]"
            value={@search_query}
            placeholder={gettext("Search products by name...")}
            class="input input-bordered input-sm w-full pl-9"
            autocomplete="off"
          />
        </form>

        <div class="flex gap-2 overflow-x-auto pb-1 scrollbar-none">
          <button
            type="button"
            phx-click="select_category"
            phx-value-id=""
            class={[
              "btn btn-xs sm:btn-sm shrink-0",
              is_nil(@selected_category_id) && "btn-primary",
              !is_nil(@selected_category_id) && "btn-ghost bg-base-200"
            ]}
          >
            {gettext("All Categories")}
          </button>
          <%= for cat <- @categories do %>
            <button
              type="button"
              phx-click="select_category"
              phx-value-id={cat.id}
              class={[
                "btn btn-xs sm:btn-sm shrink-0",
                @selected_category_id == cat.id && "btn-primary",
                @selected_category_id != cat.id && "btn-ghost bg-base-200"
              ]}
            >
              {cat.name}
            </button>
          <% end %>
        </div>
      </div>

      <div class="flex-1 lg:overflow-y-auto p-3">
        <% products = filtered_products(@categories, @selected_category_id, @search_query) %>

        <%= if Enum.empty?(products) do %>
          <div class="h-64 lg:h-full flex flex-col items-center justify-center text-base-content/40 space-y-2">
            <.icon name="hero-inbox" class="size-12 stroke-1" />
            <p class="text-sm">{gettext("No products found")}</p>
          </div>
        <% else %>
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-3 xl:grid-cols-4 gap-2">
            <%= for prod <- products do %>
              <% qty = get_cart_quantity(@cart, prod.id) %>
              <div
                phx-click="add_item"
                phx-value-product-id={prod.id}
                class={[
                  "relative cursor-pointer select-none rounded-lg p-2.5 border transition-all flex flex-col justify-between h-24 hover:shadow-md active:scale-95",
                  qty > 0 && "border-primary bg-primary/5 ring-1 ring-primary",
                  qty == 0 && "border-base-200 hover:border-primary/50 bg-base-100"
                ]}
              >
                <div class="font-medium text-xs leading-snug line-clamp-2 text-base-content">
                  {prod.name}
                </div>

                <div class="flex items-end justify-between mt-1">
                  <span class="font-mono font-bold text-xs sm:text-sm text-base-content">
                    {prod.price} ₽
                  </span>

                  <%= if qty > 0 do %>
                    <span class="badge badge-primary badge-sm font-bold font-mono">
                      {qty}
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="lg:hidden fixed bottom-0 left-0 right-0 z-30 bg-base-100 border-t border-base-300 shadow-2xl rounded-t-2xl transition-all">
        <div
          phx-click="toggle_mobile_cart"
          class="p-3 flex items-center justify-between cursor-pointer select-none bg-base-200/50 rounded-t-2xl border-b border-base-200"
        >
          <div class="flex items-center gap-2">
            <.icon name="hero-shopping-bag" class="size-5 text-primary" />
            <span class="font-bold text-sm">{gettext("Cart")}</span>
            <span class="badge badge-primary badge-sm font-mono font-bold">
              {@cart.total_quantity}
            </span>
          </div>

          <div class="flex items-center gap-2">
            <span class="font-mono font-bold text-base">{@cart.total_amount} ₽</span>
            <.icon
              name={if @mobile_cart_expanded, do: "hero-chevron-down", else: "hero-chevron-up"}
              class="size-5 text-base-content/60"
            />
          </div>
        </div>

        <%= if @mobile_cart_expanded do %>
          <div class="max-h-60 overflow-y-auto p-3 space-y-2 bg-base-100">
            <%= if Enum.empty?(@cart.items) do %>
              <p class="text-xs text-center text-base-content/50 py-4">{gettext("Cart is empty")}</p>
            <% else %>
              <div class="flex justify-between items-center mb-2 pb-2 border-b border-base-200">
                <span class="text-xs font-bold uppercase text-base-content/60">{gettext(
                  "Items in Cart"
                )}</span>
                <button
                  type="button"
                  phx-click="detach_cart"
                  class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                >
                  <.icon name="hero-trash" class="size-3.5 mr-1" />
                  {gettext("Clear Cart")}
                </button>
              </div>

              <%= for item <- @cart.items do %>
                <div class="flex items-center justify-between p-2 rounded-lg bg-base-200/60 text-xs">
                  <div class="flex-1 truncate pr-2">
                    <p class="font-medium truncate">{item.name}</p>
                    <p class="text-base-content/60 font-mono">{item.price} ₽ × {item.quantity}</p>
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
                    <span class="w-4 text-center font-bold font-mono">{item.quantity}</span>
                    <button
                      type="button"
                      phx-click="add_item"
                      phx-value-product-id={item.product_id}
                      class="btn btn-xs btn-square btn-ghost"
                    >
                      <.icon name="hero-plus" class="size-3" />
                    </button>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>

        <div class="p-3 bg-base-100">
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab="details"
            disabled={Enum.empty?(@cart.items)}
            class="btn btn-primary w-full btn-sm"
          >
            {gettext("Proceed to Checkout")}
            <.icon name="hero-arrow-right" class="size-4 ml-1" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp filtered_products(categories, category_id, search_query) do
    categories
    |> Enum.filter(fn cat -> is_nil(category_id) or cat.id == category_id end)
    |> Enum.flat_map(fn cat -> cat.products || [] end)
    |> Enum.filter(fn prod ->
      query = String.downcase(String.trim(search_query))
      query == "" or String.contains?(String.downcase(prod.name), query)
    end)
  end

  defp get_cart_quantity(cart, product_id) do
    case Enum.find(cart.items, &(&1.product_id == product_id)) do
      nil -> 0
      item -> item.quantity
    end
  end
end
