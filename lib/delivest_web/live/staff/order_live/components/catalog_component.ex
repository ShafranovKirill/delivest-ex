defmodule DelivestWeb.Staff.OrderLive.Components.CatalogComponent do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  def render_catalog(assigns) do
    ~H"""
    <div class="flex flex-col flex-1 min-h-0">
      <div class="p-3 border-b border-base-200 space-y-2 shrink-0 bg-base-100">
        <form
          id="catalog-search-form"
          phx-change="search_products"
          phx-submit="search_products"
          class="relative w-full"
        >
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-2.5 size-4 text-base-content/40 z-10 pointer-events-none"
          />
          <input
            id="catalog-search"
            type="text"
            name="search[query]"
            value={@search_query}
            placeholder={gettext("Search products by name...")}
            class="input input-bordered input-sm w-full pl-9 pr-10"
            autocomplete="off"
            phx-debounce="150"
            phx-hook=".SearchHotkey"
          />
          <kbd class="kbd kbd-xs absolute right-2.5 top-1.5 hidden lg:inline-flex">/</kbd>
        </form>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchHotkey">
          export default {
            mounted() {
              this.onKey = (event) => {
                const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)
                if (event.key === "/" && !typing) {
                  event.preventDefault()
                  this.el.focus()
                  this.el.select()
                }
              }
              window.addEventListener("keydown", this.onKey)
            },
            destroyed() {
              window.removeEventListener("keydown", this.onKey)
            }
          }
        </script>

        <div
          id="catalog-categories"
          phx-hook=".WheelScroll"
          class="flex gap-2 overflow-x-auto overscroll-x-contain pb-1"
        >
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".WheelScroll">
        export default {
          mounted() {
            this.el.addEventListener("wheel", (event) => {
              const overflows = this.el.scrollWidth > this.el.clientWidth
              if (overflows && Math.abs(event.deltaY) > Math.abs(event.deltaX)) {
                event.preventDefault()
                this.el.scrollLeft += event.deltaY
              }
            }, { passive: false })
          }
        }
      </script>

      <div class="flex-1 min-h-0 lg:overflow-y-auto p-3">
        <% products = filtered_products(@categories, @selected_category_id, @search_query) %>

        <%= if Enum.empty?(products) do %>
          <.empty_state title={gettext("No products found")} class="h-64 lg:h-full" />
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2">
            <%= for prod <- products do %>
              <% qty = get_cart_quantity(@cart, prod.id) %>
              <button
                type="button"
                id={"catalog-product-#{prod.id}"}
                phx-click="add_item"
                phx-value-product-id={prod.id}
                class={[
                  "relative flex items-center gap-2.5 text-left cursor-pointer select-none rounded-box p-2 border transition-all hover:shadow-md active:scale-[0.98]",
                  qty > 0 && "border-primary bg-primary/5 ring-1 ring-primary",
                  qty == 0 && "border-base-200 hover:border-primary/50 bg-base-100"
                ]}
              >
                <span class="size-14 shrink-0 overflow-hidden rounded-field bg-base-200 grid place-items-center">
                  <img
                    :if={prod.photo_url}
                    src={prod.photo_url}
                    alt=""
                    loading="lazy"
                    class="size-full object-cover"
                  />
                  <.icon :if={!prod.photo_url} name="hero-photo" class="size-6 text-base-content/25" />
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block font-medium text-sm leading-snug line-clamp-2">{prod.name}</span>
                  <span class="block font-mono font-bold text-sm mt-0.5">
                    {OrderHelpers.money(prod.price)}
                  </span>
                </span>
                <span
                  :if={qty > 0}
                  class="badge badge-primary badge-sm font-bold font-mono absolute -top-1.5 -right-1.5"
                >
                  {qty}
                </span>
              </button>
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
            <span class="font-mono font-bold text-base">{OrderHelpers.money(@cart.total_amount)}</span>
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
                <div class="flex items-center justify-between p-2 rounded-field bg-base-200/60 text-xs">
                  <div class="flex-1 truncate pr-2">
                    <p class="font-medium truncate">{item.name}</p>
                    <p :if={Map.get(item, :gift)} class="text-success font-medium">
                      {gettext("Gift × %{count}", count: item.quantity)}
                    </p>
                    <p :if={!Map.get(item, :gift)} class="text-base-content/60 font-mono">
                      {item.quantity} × {OrderHelpers.money(item.price)} = {OrderHelpers.money(
                        item.total_price
                      )}
                    </p>
                  </div>
                  <div :if={!Map.get(item, :gift)} class="flex items-center gap-1 shrink-0">
                    <button
                      type="button"
                      phx-click="remove_item"
                      phx-value-product-id={Map.get(item, :key, item.product_id)}
                      class="btn btn-xs btn-square btn-ghost"
                    >
                      <.icon name="hero-minus" class="size-3" />
                    </button>
                    <span class="w-4 text-center font-bold font-mono">{item.quantity}</span>
                    <button
                      type="button"
                      phx-click="add_item"
                      phx-value-product-id={Map.get(item, :key, item.product_id)}
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
    case Enum.find(cart.items, &(&1.product_id == product_id and !Map.get(&1, :gift, false))) do
      nil -> 0
      item -> item.quantity
    end
  end
end
