defmodule DelivestWeb.Staff.OrderLive.OrderForm do
  use DelivestWeb, :live_view

  alias Delivest.Net.Catalogs
  alias Delivest.Oms.{Carts, Order, Orders}

  on_mount {DelivestWeb.Hooks.Permission, "order.create"}

  @impl true
  def mount(params, _session, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    {:ok, cart} = Carts.get_or_create_cart(staff_id: staff.id, branch_id: branch_id)
    {:ok, categories} = Catalogs.get_menu_for_branch(branch_id)

    {order, cart, page_title} =
      case Map.get(params, "id") do
        nil ->
          {%Order{}, cart, gettext("New Order")}

        id ->
          existing_order = Orders.get_order!(id)
          updated_cart = Orders.populate_cart_from_order(existing_order, cart.id)

          {existing_order, updated_cart,
           gettext("Edit Order #%{number}", number: existing_order.number)}
      end

    order =
      case order.client do
        %{customer_phone: customer_phone, customer_name: name} ->
          %{order | customer_phone: customer_phone, customer_name: name}

        _ ->
          order
      end

    {address, raw_order_params} =
      order
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id, :inserted_at, :updated_at, :items, :branch, :staff, :client])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.pop("address")

    default_params =
      Map.merge(raw_order_params, %{
        "branch_id" => branch_id,
        "cart_id" => cart.id
      })

    default_params =
      case address do
        %_struct{} = addr ->
          addr_map =
            addr
            |> Map.from_struct()
            |> Map.drop([
              :__meta__,
              :id,
              :inserted_at,
              :updated_at,
              :order_id,
              :street,
              :district,
              :city
            ])
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

          Map.put(default_params, "address", addr_map)

        _ ->
          default_params
      end

    order_changeset = Order.changeset(order, default_params)

    {:ok,
     socket
     |> assign(
       order: order,
       is_edit: order.id != nil,
       page_title: page_title,
       branch_id: branch_id,
       cart: cart,
       categories: categories,
       selected_category_id: nil,
       search_query: "",
       active_tab: :cart,
       mobile_cart_expanded: false,
       form: to_form(order_changeset)
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  def handle_event("toggle_mobile_cart", _params, socket) do
    {:noreply, assign(socket, mobile_cart_expanded: !socket.assigns.mobile_cart_expanded)}
  end

  def handle_event("select_category", %{"id" => id}, socket) do
    cat_id = if id == "", do: nil, else: id
    {:noreply, assign(socket, selected_category_id: cat_id)}
  end

  def handle_event("search_products", %{"search" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  def handle_event("add_item", %{"product-id" => product_id}, socket) do
    case Carts.add_item(socket.assigns.cart.id, product_id) do
      {:ok, _item, updated_cart} ->
        {:noreply, assign(socket, cart: updated_cart)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add product to cart."))}
    end
  end

  def handle_event("remove_item", %{"product-id" => product_id}, socket) do
    case Carts.remove_item(socket.assigns.cart.id, product_id) do
      {:ok, _status, updated_cart} ->
        {:noreply, assign(socket, cart: updated_cart)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"product-id" => product_id}, socket) do
    case Carts.remove_item(socket.assigns.cart.id, product_id, all: true) do
      {:ok, _status, updated_cart} ->
        {:noreply, assign(socket, cart: updated_cart)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("validate_order", %{"order" => params}, socket) do
    full_params =
      params
      |> Map.put("cart_id", socket.assigns.cart.id)
      |> Map.put("branch_id", socket.assigns.branch_id)

    changeset =
      socket.assigns.order
      |> Order.changeset(full_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_order", %{"order" => order_params}, socket) do
    if socket.assigns.is_edit do
      update_existing_order(socket, order_params)
    else
      create_new_order(socket, order_params)
    end
  end

  defp create_new_order(socket, order_params) do
    full_order_params =
      order_params
      |> Map.put("cart_id", socket.assigns.cart.id)
      |> Map.put("branch_id", socket.assigns.branch_id)
      |> Map.put("staff_id", socket.assigns.current_staff.id)

    case Orders.create_order(full_order_params) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Order created successfully"))
         |> push_navigate(to: ~p"/staff/orders")}

      {:error, _failed_step, %Ecto.Changeset{} = err_changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(err_changeset, :action, :insert)))}

      {:error, _failed_step, reason} ->
        {:noreply,
         put_flash(socket, :error, "#{gettext("Failed to create order")}: #{inspect(reason)}")}
    end
  end

  defp update_existing_order(socket, order_params) do
    items_attrs =
      Enum.map(socket.assigns.cart.items, fn item ->
        %{
          "product_id" => item.product_id,
          "quantity" => item.quantity
        }
      end)

    full_order_params =
      order_params
      |> Map.put("items", items_attrs)
      |> Map.put("branch_id", socket.assigns.branch_id)

    case Orders.update_order(socket.assigns.order, full_order_params) do
      {:ok, _updated_order} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Order updated successfully"))
         |> push_navigate(to: ~p"/staff/orders")}

      {:error, _failed_step, %Ecto.Changeset{} = err_changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(err_changeset, :action, :update)))}

      {:error, _failed_step, reason} ->
        {:noreply,
         put_flash(socket, :error, "#{gettext("Failed to update order")}: #{inspect(reason)}")}
    end
  end

  defp filtered_products(categories, category_id, search_query) do
    categories
    |> Enum.filter(fn cat -> is_nil(category_id) or cat.id == category_id end)
    |> Enum.flat_map(fn cat -> cat.products || [] end)
    |> Enum.filter(fn prod ->
      query = String.downcase(String.trim(search_query))

      if query == "" do
        true
      else
        String.contains?(String.downcase(prod.name), query)
      end
    end)
  end

  defp get_cart_quantity(cart, product_id) do
    case Enum.find(cart.items, &(&1.product_id == product_id)) do
      nil -> 0
      item -> item.quantity
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full min-h-screen lg:min-h-0 lg:h-[calc(100vh-4rem)] flex flex-col lg:flex-row overflow-y-auto lg:overflow-hidden gap-3 bg-base-200 pb-20 lg:pb-0">
      <div class="lg:hidden shrink-0 bg-base-100 p-2 rounded-box border border-base-300 shadow-sm sticky top-0 z-20">
        <div class="tabs tabs-boxed grid grid-cols-2">
          <button
            type="button"
            class={["tab text-xs", @active_tab == :cart && "tab-active font-bold"]}
            phx-click="switch_tab"
            phx-value-tab="cart"
          >
            <.icon name="hero-shopping-bag" class="size-4 mr-1" />
            {gettext("1. Menu & Cart")}
            <%= if @cart.total_quantity > 0 do %>
              <span class="badge badge-xs badge-primary ml-1 font-mono">{@cart.total_quantity}</span>
            <% end %>
          </button>
          <button
            type="button"
            class={["tab text-xs", @active_tab == :details && "tab-active font-bold"]}
            phx-click="switch_tab"
            phx-value-tab="details"
          >
            <.icon name="hero-document-text" class="size-4 mr-1" />
            {gettext("2. Checkout")}
          </button>
        </div>
      </div>

      <div class={[
        "w-full lg:w-7/12 xl:w-8/12 flex flex-col bg-base-100 rounded-box border border-base-200 lg:overflow-hidden shadow-sm",
        @active_tab != :cart && "hidden lg:flex"
      ]}>
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
                <p class="text-xs text-center text-base-content/50 py-4">
                  {gettext("Cart is empty")}
                </p>
              <% else %>
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

      <div class={[
        "w-full lg:w-5/12 xl:w-4/12 flex flex-col bg-base-100 rounded-box border border-base-200 lg:overflow-hidden shadow-sm",
        @active_tab != :details && "hidden lg:flex"
      ]}>
        <div class="p-3 border-b border-base-200 shrink-0 hidden lg:block">
          <div class="tabs tabs-boxed grid grid-cols-2">
            <button
              type="button"
              class={["tab text-xs", @active_tab == :cart && "tab-active font-bold"]}
              phx-click="switch_tab"
              phx-value-tab="cart"
            >
              <.icon name="hero-shopping-bag" class="size-4 mr-1.5" />
              {gettext("Cart")}
              <%= if @cart.total_quantity > 0 do %>
                <span class="badge badge-sm badge-primary ml-1 font-mono">
                  {@cart.total_quantity}
                </span>
              <% end %>
            </button>
            <button
              type="button"
              class={["tab text-xs", @active_tab == :details && "tab-active font-bold"]}
              phx-click="switch_tab"
              phx-value-tab="details"
            >
              <.icon name="hero-document-text" class="size-4 mr-1.5" />
              {gettext("Order Details")}
            </button>
          </div>
        </div>

        <div class="flex-1 lg:overflow-y-auto p-3 lg:p-4">
          <div class={[@active_tab != :cart && "hidden lg:hidden"]}>
            <%= if Enum.empty?(@cart.items) do %>
              <div class="h-64 flex flex-col items-center justify-center text-base-content/40 space-y-2">
                <.icon name="hero-shopping-cart" class="size-12 stroke-1" />
                <p class="text-sm font-medium">{gettext("Cart is empty")}</p>
              </div>
            <% else %>
              <div class="space-y-2">
                <%= for item <- @cart.items do %>
                  <div class="flex items-center justify-between p-2.5 rounded-box bg-base-200/60 border border-base-200">
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
                      <span class="w-5 text-center text-xs font-bold font-mono">
                        {item.quantity}
                      </span>
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
                <% end %>
              </div>
            <% end %>
          </div>

          <div class={[@active_tab != :details && "hidden lg:hidden"]}>
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
                <%= for item <- @cart.items do %>
                  <div class="flex justify-between text-xs">
                    <span class="truncate pr-2">{item.name} × {item.quantity}</span>
                    <span class="font-mono font-bold shrink-0">{item.total_price} ₽</span>
                  </div>
                <% end %>
              </div>
            </div>

            <.form
              for={@form}
              id="order-details-form"
              phx-change="validate_order"
              phx-submit="save_order"
              class="space-y-3"
            >
              <div class="form-control">
                <label class="label text-xs font-bold uppercase text-base-content/60 p-0 mb-1">
                  {gettext("Customer Info")}
                </label>
                <div class="space-y-2">
                  <.input
                    field={@form[:customer_phone]}
                    type="text"
                    label={gettext("Phone")}
                    placeholder="+79991112233"
                    required
                  />
                  <.input field={@form[:customer_name]} type="text" label={gettext("Client Name")} />
                </div>
              </div>

              <div class="divider text-xs font-bold uppercase text-base-content/40 my-2">
                {gettext("Options")}
              </div>

              <.input
                field={@form[:fulfillment_type]}
                type="select"
                label={gettext("Fulfillment Type")}
                options={[
                  {gettext("Dine In"), "dine_in"},
                  {gettext("Delivery"), "delivery"},
                  {gettext("Pickup"), "pickup"}
                ]}
              />

              <.input
                field={@form[:payment_method]}
                type="select"
                label={gettext("Payment Method")}
                options={[
                  {gettext("Cash"), "cash"},
                  {gettext("Card Offline"), "card_offline"}
                ]}
              />

              <% fulfillment_type = Ecto.Changeset.get_field(@form.source, :fulfillment_type) %>
              <%= if to_string(fulfillment_type) == "delivery" do %>
                <div class="p-3 bg-base-200/50 rounded-box border border-base-300 space-y-2">
                  <span class="text-xs font-bold">{gettext("Delivery Address")}</span>
                  <.inputs_for :let={address_form} field={@form[:address]}>
                    <.input
                      field={address_form[:city_name]}
                      type="text"
                      label={gettext("City")}
                      required
                    />
                    <.input
                      field={address_form[:street_name]}
                      type="text"
                      label={gettext("Street")}
                      required
                    />
                    <div class="grid grid-cols-2 gap-2">
                      <.input
                        field={address_form[:house_number]}
                        type="text"
                        label={gettext("House / Building")}
                        required
                      />
                      <.input
                        field={address_form[:building]}
                        type="text"
                        label={gettext("Building/Block")}
                      />
                    </div>
                    <div class="grid grid-cols-3 gap-2">
                      <.input field={address_form[:entrance]} type="text" label={gettext("Entrance")} />
                      <.input field={address_form[:floor]} type="text" label={gettext("Floor")} />
                      <.input
                        field={address_form[:apartment]}
                        type="text"
                        label={gettext("Apartment")}
                      />
                    </div>
                  </.inputs_for>
                </div>
              <% end %>

              <.input field={@form[:comment]} type="textarea" label={gettext("Comment")} rows={2} />
            </.form>
          </div>
        </div>

        <div class="p-3 lg:p-4 border-t border-base-200 bg-base-100 shrink-0 space-y-2">
          <div class="flex justify-between items-center text-base lg:text-lg font-bold">
            <span>{gettext("Total:")}</span>
            <span class="font-mono text-lg lg:text-xl">{@cart.total_amount} ₽</span>
          </div>

          <%= if @active_tab == :cart do %>
            <button
              type="button"
              phx-click="switch_tab"
              phx-value-tab="details"
              disabled={Enum.empty?(@cart.items)}
              class="btn btn-primary w-full"
            >
              {gettext("Proceed to Checkout")}
              <.icon name="hero-arrow-right" class="size-4 ml-1" />
            </button>
          <% else %>
            <div class="flex gap-2">
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
                disabled={Enum.empty?(@cart.items)}
                class="btn btn-success flex-1 text-white"
              >
                <.icon name="hero-check" class="size-5 mr-1" />
                <%= if @is_edit do %>
                  {gettext("Save Changes")}
                <% else %>
                  {gettext("Submit Order")}
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
