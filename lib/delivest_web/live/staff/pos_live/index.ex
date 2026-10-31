defmodule DelivestWeb.Staff.PosLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Money, Oms, Pos}
  alias Delivest.Net.{Catalogs, Modifiers}
  alias Delivest.Oms.{Carts, Order, Orders}
  alias DelivestWeb.Staff.OrderLive.{SaveErrors, StatusErrors}

  @impl true
  def mount(_params, _session, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns
    {:ok, branch} = Identity.get_branch(branch.id, preload: :info)

    if Pos.available?(branch) do
      if connected?(socket), do: Orders.subscribe(branch.id)
      {:ok, categories} = Catalogs.get_menu_for_branch(branch.id)
      {:ok, cart} = Pos.cart(staff, branch.id)

      {:ok,
       socket
       |> assign(
         page_title: gettext("POS"),
         categories: categories,
         category_id: nil,
         query: "",
         picker: nil,
         screen: :sale,
         method: "cash",
         cash_given: nil,
         done: nil,
         ready: Pos.ready(branch.id)
       )
       |> assign_cart(cart)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("The branch works on the POS of its CRM"))
       |> redirect(to: ~p"/staff/b/#{branch}/dashboard")}
    end
  end

  @impl true
  def handle_event("category", %{"id" => id}, socket),
    do: {:noreply, assign(socket, category_id: if(id == "", do: nil, else: id))}

  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("add", %{"id" => id}, socket) do
    case Map.get(Modifiers.for_products([id]), id, []) do
      [] -> add(socket, id, nil)
      groups -> {:noreply, assign(socket, picker: %{product_id: id, groups: groups})}
    end
  end

  def handle_event("pick", params, socket) do
    chosen =
      params
      |> Map.get("modifiers", %{})
      |> Map.values()
      |> List.flatten()
      |> Enum.reject(&(&1 == ""))

    socket |> assign(picker: nil) |> add(socket.assigns.picker.product_id, chosen)
  end

  def handle_event("close_picker", _params, socket), do: {:noreply, assign(socket, picker: nil)}

  def handle_event("more", %{"key" => key}, socket) do
    {product_id, _modifier_key} = Carts.parse_item_key(key)
    add(socket, product_id, selection(socket.assigns.cart, key))
  end

  def handle_event("less", %{"key" => key}, socket),
    do: socket.assigns.cart.id |> Oms.remove_item(key) |> cart_result(socket)

  def handle_event("clear", _params, socket) do
    case Oms.clear_cart(socket.assigns.cart.id) do
      {:ok, cart} -> {:noreply, assign_cart(socket, cart)}
      _error -> {:noreply, socket}
    end
  end

  def handle_event("type", %{"type" => type}, socket) when type in ~w(dine_in pickup) do
    case Oms.update_cart_context(socket.assigns.cart.id, %{fulfillment_type: type, client_id: nil}) do
      {:ok, cart} -> {:noreply, assign_cart(socket, cart)}
      _error -> {:noreply, socket}
    end
  end

  def handle_event("promo", %{"code" => code}, socket) do
    case Oms.apply_promo_code(socket.assigns.cart.id, code) do
      {:ok, cart} -> {:noreply, assign_cart(socket, cart)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("remove_promo", _params, socket) do
    case Oms.remove_promo_code(socket.assigns.cart.id) do
      {:ok, cart} -> {:noreply, assign_cart(socket, cart)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pay", _params, %{assigns: %{cart: %{items: [_ | _]}}} = socket),
    do: {:noreply, assign(socket, screen: :payment, method: "cash", cash_given: nil)}

  def handle_event("pay", _params, socket), do: {:noreply, socket}

  def handle_event("screen", %{"to" => to}, socket) when to in ~w(sale handout),
    do: {:noreply, assign(socket, screen: String.to_existing_atom(to), done: nil)}

  def handle_event("method", %{"method" => method}, socket) when method in ~w(cash card),
    do: {:noreply, assign(socket, method: method)}

  def handle_event("cash", %{"cash" => value}, socket),
    do: {:noreply, assign(socket, cash_given: kopecks(value))}

  def handle_event("bill", %{"amount" => amount}, socket),
    do: {:noreply, assign(socket, cash_given: String.to_integer(amount))}

  def handle_event("confirm", _params, socket) do
    %{current_staff: staff, cart: cart, method: method, cash_given: cash_given} = socket.assigns

    params = %{
      "fulfillment_type" => cart.fulfillment_type || "dine_in",
      "method" => method,
      "cash_given" => cash_given
    }

    case Pos.checkout(staff, cart, params) do
      {:ok, order} ->
        {:ok, cart} = Pos.cart(staff, socket.assigns.current_branch.id)

        {:noreply,
         socket
         |> assign(screen: :done, done: %{order: order, change: change(order, socket.assigns)})
         |> assign_cart(cart)}

      {:error, _step, reason} ->
        {:noreply, put_flash(socket, :error, save_error(reason))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, save_error(reason))}
    end
  end

  def handle_event("hand_out", %{"id" => id}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Pos.hand_out(staff, branch.id, id) do
        {:ok, _order} -> socket
        error -> put_flash(socket, :error, StatusErrors.message(error))
      end

    {:noreply, assign(socket, ready: Pos.ready(branch.id))}
  end

  @impl true
  def handle_info({Orders, _event, _order}, socket),
    do: {:noreply, assign(socket, ready: Pos.ready(socket.assigns.current_branch.id))}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp add(socket, product_id, selection) do
    case Carts.add_item(socket.assigns.cart.id, product_id, 1, selection) do
      {:ok, _item, cart} ->
        {:noreply, assign_cart(socket, cart)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Product is unavailable"))}
    end
  end

  defp cart_result({:ok, _status, cart}, socket), do: {:noreply, assign_cart(socket, cart)}
  defp cart_result(_error, socket), do: {:noreply, socket}

  defp assign_cart(socket, %{fulfillment_type: nil} = cart) do
    case Oms.update_cart_context(cart.id, %{fulfillment_type: "dine_in", client_id: nil}) do
      {:ok, cart} -> assign(socket, cart: cart)
      _error -> assign(socket, cart: cart)
    end
  end

  defp assign_cart(socket, cart), do: assign(socket, cart: cart)

  defp selection(cart, key) do
    case Enum.find(cart.items, &(Map.get(&1, :key) == key)) do
      %{modifiers: modifiers} -> Enum.map(modifiers, &%{"id" => &1.id, "quantity" => &1.quantity})
      _missing -> nil
    end
  end

  defp change(%Order{total_amount: total}, %{method: "cash", cash_given: given}),
    do: Pos.change(total, given)

  defp change(_order, _assigns), do: nil

  defp save_error(%Ecto.Changeset{}), do: gettext("Validation error")
  defp save_error(reason), do: SaveErrors.message(reason)

  defp kopecks(value) do
    case Float.parse(String.replace(value, ",", ".")) do
      {rubles, _rest} when rubles > 0 -> round(rubles * 100)
      _invalid -> nil
    end
  end

  defp products(categories, category_id, query) do
    query = query |> String.trim() |> String.downcase()

    categories
    |> Enum.filter(&(is_nil(category_id) or &1.id == category_id))
    |> Enum.flat_map(&(&1.products || []))
    |> Enum.filter(&(query == "" or String.contains?(String.downcase(&1.name), query)))
  end

  defp bills(total) do
    [total | Enum.map([10_000, 50_000, 100_000, 200_000, 500_000], &(div(total, &1) * &1 + &1))]
    |> Enum.uniq()
    |> Enum.take(4)
  end

  defp key(item), do: Map.get(item, :key, item.product_id)

  @impl true
  def render(assigns) do
    ~H"""
    <div id="pos" class="flex h-screen flex-col select-none">
      <header class="flex items-center gap-2 border-b border-base-300 bg-base-100 px-3 py-2">
        <span class="text-lg font-bold">{gettext("POS")}</span>
        <span class="text-base-content/60">{@current_branch.name}</span>
        <div class="ml-4 join">
          <button
            id="pos-tab-sale"
            phx-click="screen"
            phx-value-to="sale"
            class={["btn join-item", @screen != :handout && "btn-primary"]}
          >
            {gettext("Sale")}
          </button>
          <button
            id="pos-tab-handout"
            phx-click="screen"
            phx-value-to="handout"
            class={["btn join-item", @screen == :handout && "btn-primary"]}
          >
            {gettext("Hand out")}
            <span :if={@ready != []} class="badge badge-sm">{length(@ready)}</span>
          </button>
        </div>
        <.link navigate={~p"/staff/b/#{@current_branch}/orders"} class="btn btn-ghost ml-auto">
          <.icon name="hero-arrow-left-on-rectangle" class="size-5" /> {gettext("Exit")}
        </.link>
      </header>

      <div :if={@screen == :sale} class="flex min-h-0 flex-1">
        <aside class="w-44 shrink-0 space-y-1 overflow-y-auto border-r border-base-300 bg-base-100 p-2">
          <button
            phx-click="category"
            phx-value-id=""
            class={["btn btn-block justify-start", is_nil(@category_id) && "btn-primary"]}
          >
            {gettext("All")}
          </button>
          <button
            :for={category <- @categories}
            id={"pos-category-#{category.id}"}
            phx-click="category"
            phx-value-id={category.id}
            class={[
              "btn btn-block h-auto min-h-12 justify-start text-left",
              @category_id == category.id && "btn-primary"
            ]}
          >
            {category.name}
          </button>
        </aside>

        <section class="relative flex min-w-0 flex-1 flex-col">
          <form id="pos-search-form" phx-change="search" phx-submit="search" class="p-3">
            <input
              id="pos-search"
              name="query"
              value={@query}
              placeholder={gettext("Search products by name...")}
              autocomplete="off"
              phx-debounce="150"
              class="input input-lg w-full"
            />
          </form>
          <div class="grid flex-1 auto-rows-min grid-cols-2 gap-2 overflow-y-auto p-3 pt-0 md:grid-cols-3 xl:grid-cols-4">
            <button
              :for={product <- products(@categories, @category_id, @query)}
              id={"pos-product-#{product.id}"}
              phx-click="add"
              phx-value-id={product.id}
              class="flex min-h-24 flex-col justify-between rounded-box border border-base-300 bg-base-100 p-3 text-left active:scale-[0.98]"
            >
              <span class="line-clamp-2 font-medium leading-snug">{product.name}</span>
              <span class="font-mono text-lg font-bold">{Money.format(product.price)}</span>
            </button>
          </div>

          <form
            :if={@picker}
            id="pos-modifiers"
            phx-submit="pick"
            class="absolute inset-x-0 bottom-0 max-h-[70%] space-y-4 overflow-y-auto rounded-t-box border-t border-base-300 bg-base-100 p-4 shadow-2xl"
          >
            <fieldset :for={group <- @picker.groups} class="space-y-2">
              <legend class="font-bold">
                {group.name}
                <span class="text-xs font-normal text-base-content/60">
                  {gettext("from %{min} to %{max}", min: group.min, max: group.max)}
                </span>
              </legend>
              <input type="hidden" name={"modifiers[#{group.id}][]"} value="" />
              <div class="flex flex-wrap gap-2">
                <label
                  :for={modifier <- group.modifiers}
                  class="btn btn-lg h-auto has-checked:btn-primary"
                >
                  <input
                    type={if group.max == 1, do: "radio", else: "checkbox"}
                    name={"modifiers[#{group.id}][]"}
                    value={modifier.id}
                    checked={modifier.is_default}
                    class="hidden"
                  />
                  {modifier.name}
                  <span :if={modifier.price > 0} class="font-mono text-sm">
                    +{Money.format(modifier.price)}
                  </span>
                </label>
              </div>
            </fieldset>
            <div class="flex gap-2">
              <button type="button" phx-click="close_picker" class="btn btn-lg btn-ghost flex-1">
                {gettext("Cancel")}
              </button>
              <button class="btn btn-lg btn-primary flex-1">{gettext("Add")}</button>
            </div>
          </form>
        </section>

        <div class="flex flex-col">
          <form id="pos-promo" phx-submit="promo" class="flex gap-2 p-3">
            <input
              name="code"
              value={@cart.promo_code}
              placeholder={gettext("Promo code")}
              class="input min-w-0 flex-1"
            />
            <button class="btn">{gettext("Apply")}</button>
            <button
              :if={@cart.promo_code}
              type="button"
              phx-click="remove_promo"
              class="btn btn-ghost"
            >{gettext("Remove")}</button>
          </form>
          <.check cart={@cart} />
        </div>
      </div>

      <div
        :if={@screen == :payment}
        id="pos-payment"
        class="mx-auto w-full max-w-xl flex-1 space-y-6 p-6"
      >
        <p class="text-center text-base-content/60">{gettext("To pay")}</p>
        <p id="pos-total" class="text-center font-mono text-5xl font-black">
          {Money.format(@cart.total_amount)}
        </p>
        <div class="grid grid-cols-2 gap-2">
          <button
            id="pos-method-cash"
            phx-click="method"
            phx-value-method="cash"
            class={["btn btn-lg h-20 text-xl", @method == "cash" && "btn-primary"]}
          >
            <.icon name="hero-banknotes" class="size-6" /> {gettext("Cash")}
          </button>
          <button
            id="pos-method-card"
            phx-click="method"
            phx-value-method="card"
            class={["btn btn-lg h-20 text-xl", @method == "card" && "btn-primary"]}
          >
            <.icon name="hero-credit-card" class="size-6" /> {gettext("Card")}
          </button>
        </div>

        <div :if={@method == "cash"} class="space-y-3">
          <form id="pos-cash" phx-change="cash">
            <input
              name="cash"
              inputmode="decimal"
              value={@cash_given && @cash_given / 100}
              placeholder={gettext("Received from the customer")}
              autocomplete="off"
              class="input input-lg w-full text-center font-mono text-2xl"
            />
          </form>
          <div class="grid grid-cols-4 gap-2">
            <button
              :for={bill <- bills(@cart.total_amount)}
              phx-click="bill"
              phx-value-amount={bill}
              class="btn btn-lg font-mono"
            >
              {Money.format(bill)}
            </button>
          </div>
          <p :if={@cash_given} id="pos-change" class="text-center text-2xl">
            <%= case Pos.change(@cart.total_amount, @cash_given) do %>
              <% nil -> %>
                <span class="text-error">{gettext("Not enough")}</span>
              <% change -> %>
                {gettext("Change")} <b class="font-mono">{Money.format(change)}</b>
            <% end %>
          </p>
        </div>

        <div class="grid grid-cols-3 gap-2">
          <button phx-click="screen" phx-value-to="sale" class="btn btn-lg btn-ghost">
            {gettext("Back")}
          </button>
          <button
            id="pos-confirm"
            phx-click="confirm"
            phx-disable-with={gettext("Saving...")}
            disabled={
              @method == "cash" and @cash_given != nil and
                is_nil(Pos.change(@cart.total_amount, @cash_given))
            }
            class="btn btn-lg btn-success col-span-2"
          >
            {gettext("Paid")}
          </button>
        </div>
      </div>

      <div
        :if={@screen == :done}
        id="pos-done"
        class="mx-auto flex max-w-xl flex-1 flex-col items-center justify-center gap-4 p-6 text-center"
      >
        <.icon name="hero-check-circle" class="size-20 text-success" />
        <p class="text-base-content/60">{gettext("Order number")}</p>
        <p class="font-mono text-6xl font-black">{Order.short_number(@done.order)}</p>
        <p :if={@done.change} id="pos-done-change" class="text-2xl">
          {gettext("Change")} <b class="font-mono">{Money.format(@done.change)}</b>
        </p>
        <button
          id="pos-next"
          phx-click="screen"
          phx-value-to="sale"
          class="btn btn-lg btn-primary w-64"
        >
          {gettext("Next order")}
        </button>
      </div>

      <div :if={@screen == :handout} id="pos-handout" class="flex-1 overflow-y-auto p-4">
        <p :if={@ready == []} class="py-16 text-center text-base-content/50">
          {gettext("No ready orders")}
        </p>
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <button
            :for={order <- @ready}
            id={"pos-ready-#{order.id}"}
            phx-click="hand_out"
            phx-value-id={order.id}
            class="btn h-28 flex-col gap-1 text-left"
          >
            <span class="font-mono text-4xl font-black">{Order.short_number(order)}</span>
            <span class="text-sm">{gettext("Hand out")}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :cart, :map, required: true

  defp check(assigns) do
    ~H"""
    <aside
      id="pos-check"
      class="flex w-80 shrink-0 flex-col border-l border-base-300 bg-base-100 xl:w-96"
    >
      <div class="join m-3">
        <button
          id="pos-type-dine_in"
          phx-click="type"
          phx-value-type="dine_in"
          class={["btn join-item flex-1", @cart.fulfillment_type in [nil, "dine_in"] && "btn-primary"]}
        >
          {gettext("Dine in")}
        </button>
        <button
          id="pos-type-pickup"
          phx-click="type"
          phx-value-type="pickup"
          class={["btn join-item flex-1", @cart.fulfillment_type == "pickup" && "btn-primary"]}
        >
          {gettext("Takeaway")}
        </button>
      </div>

      <div class="flex-1 space-y-2 overflow-y-auto px-3">
        <p :if={@cart.items == []} class="py-10 text-center text-base-content/50">
          {gettext("The check is empty")}
        </p>
        <div
          :for={item <- @cart.items}
          id={"pos-item-#{String.replace(key(item), ":", "-")}"}
          class="flex items-center gap-2 border-b border-base-200 pb-2"
        >
          <div class="min-w-0 flex-1">
            <p class="font-medium leading-snug">{item.name}</p>
            <p :if={item.modifiers != []} class="text-xs text-base-content/60">
              {Enum.map_join(item.modifiers, ", ", & &1.name)}
            </p>
            <p class="font-mono text-sm">{Money.format(item.total_price)}</p>
          </div>
          <button
            :if={!Map.get(item, :gift, false)}
            phx-click="less"
            phx-value-key={key(item)}
            class="btn btn-square"
          >
            <.icon name="hero-minus" class="size-4" />
          </button>
          <span class="w-6 text-center font-mono font-bold">{item.quantity}</span>
          <button
            :if={!Map.get(item, :gift, false)}
            phx-click="more"
            phx-value-key={key(item)}
            class="btn btn-square"
          >
            <.icon name="hero-plus" class="size-4" />
          </button>
        </div>
      </div>

      <div class="space-y-2 border-t border-base-300 p-3">
        <div class="flex items-baseline justify-between">
          <span class="text-base-content/60">{gettext("Total")}</span>
          <span id="pos-check-total" class="font-mono text-3xl font-black">
            {Money.format(@cart.total_amount)}
          </span>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="clear"
            disabled={@cart.items == []}
            data-confirm={gettext("Clear the check?")}
            class="btn btn-lg btn-ghost"
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
          <button
            id="pos-pay"
            phx-click="pay"
            disabled={@cart.items == []}
            class="btn btn-lg btn-primary flex-1"
          >
            {gettext("Pay")}
          </button>
        </div>
      </div>
    </aside>
    """
  end
end
