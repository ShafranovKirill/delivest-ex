defmodule DelivestWeb.Staff.OrderLive.OrderForm do
  alias Delivest.Oms
  use DelivestWeb, :live_view

  alias Delivest.Net.Catalogs
  alias Delivest.Oms.{Carts, Order, Orders}
  alias DelivestWeb.Staff.OrderLive.Components.{CatalogComponent, DetailsComponent}

  on_mount {DelivestWeb.Hooks.Permission, "order.create"}

  @impl true
  def mount(params, _session, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    {:ok, categories} = Catalogs.get_menu_for_branch(branch_id)

    {order, cart, page_title} =
      case Map.get(params, "id") do
        nil ->
          {:ok, default_cart} = Carts.get_or_create_cart(staff_id: staff.id, branch_id: branch_id)
          {%Order{}, default_cart, gettext("New Order")}

        id ->
          existing_order = Orders.get_order(id)

          cart =
            Carts.get_cart_by_id(existing_order.cart_id) ||
              case Carts.get_or_create_cart(staff_id: staff.id, branch_id: branch_id) do
                {:ok, c} -> c
              end

          {existing_order, cart, gettext("Edit Order #%{number}", number: existing_order.number)}
      end

    {customer_phone, customer_name} =
      case order.client do
        %Ecto.Association.NotLoaded{} ->
          {nil, nil}

        %{} = client ->
          {Map.get(client, :phone) || Map.get(client, :customer_phone),
           Map.get(client, :name) || Map.get(client, :customer_name)}

        _ ->
          {nil, nil}
      end

    order = %{order | customer_phone: customer_phone, customer_name: customer_name}

    {address, raw_order_params} =
      order
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id, :inserted_at, :updated_at, :items, :branch, :staff, :client])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.pop("address")

    {crm_info, raw_order_params} = Map.pop(raw_order_params, "crm_info")

    default_params =
      raw_order_params
      |> Map.merge(%{"branch_id" => branch_id, "cart_id" => cart.id})
      |> Map.put_new("customer_phone", "+7")

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

    default_params =
      case crm_info do
        %_struct{} = crm ->
          crm_map =
            crm
            |> Map.from_struct()
            |> Map.drop([:__meta__, :id, :inserted_at, :updated_at])
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

          Map.put(default_params, "crm_info", crm_map)

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
  def handle_event("detach_cart", _params, socket) do
    current_cart = socket.assigns.cart

    case Carts.clear_cart(current_cart.id) do
      {:ok, updated_cart} ->
        {:noreply,
         socket
         |> assign(cart: updated_cart)
         |> put_flash(:info, gettext("Cart has been cleared"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to clear cart"))}
    end
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
      {:ok, _status, updated_cart} -> {:noreply, assign(socket, cart: updated_cart)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"product-id" => product_id}, socket) do
    case Carts.remove_item(socket.assigns.cart.id, product_id, all: true) do
      {:ok, _status, updated_cart} -> {:noreply, assign(socket, cart: updated_cart)}
      {:error, _reason} -> {:noreply, socket}
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

    changeset =
      case Ecto.Changeset.get_change(changeset, :address) do
        %Ecto.Changeset{} = addr_cs ->
          Ecto.Changeset.put_change(changeset, :address, %{addr_cs | action: :validate})

        _ ->
          changeset
      end

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_order", %{"order" => order_params}, socket) do
    if socket.assigns.is_edit,
      do: update_existing_order(socket, order_params),
      else: create_new_order(socket, order_params)
  end

  defp create_new_order(socket, order_params) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id
    current_cart = socket.assigns.cart

    full_order_params =
      order_params
      |> Map.put("cart_id", current_cart.id)
      |> Map.put("branch_id", branch_id)
      |> Map.put("staff_id", staff.id)

    case Oms.create_order(full_order_params) do
      {:ok, _result} ->
        Carts.detach_staff_cart(current_cart.id)
        {:ok, _new_cart} = Carts.get_or_create_cart(staff_id: staff.id, branch_id: branch_id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Order created successfully"))
         |> push_navigate(to: ~p"/staff/orders")}

      {:error, _failed_step, %Ecto.Changeset{} = err_changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Validation error"))
         |> assign(form: to_form(Map.put(err_changeset, :action, :insert)))}

      {:error, _failed_step, reason} ->
        {:noreply,
         put_flash(socket, :error, "#{gettext("Failed to create order")}: #{inspect(reason)}")}
    end
  end

  defp update_existing_order(socket, order_params) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id
    current_cart = socket.assigns.cart

    full_order_params =
      order_params |> Map.put("cart_id", current_cart.id) |> Map.put("branch_id", branch_id)

    case Orders.update_order(socket.assigns.order, full_order_params) do
      {:ok, _updated_order} ->
        Carts.detach_staff_cart(current_cart.id)
        {:ok, _new_cart} = Carts.get_or_create_cart(staff_id: staff.id, branch_id: branch_id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Order updated successfully"))
         |> push_navigate(to: ~p"/staff/orders")}

      {:error, _failed_step, %Ecto.Changeset{} = err_changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Validation error"))
         |> assign(form: to_form(Map.put(err_changeset, :action, :update)))}

      {:error, _failed_step, reason} ->
        {:noreply,
         put_flash(socket, :error, "#{gettext("Failed to update order")}: #{inspect(reason)}")}
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

      <!-- Левая колонка: Каталог товаров -->
      <div class={[
        "w-full lg:w-7/12 xl:w-8/12 flex flex-col bg-base-100 rounded-box border border-base-200 lg:overflow-hidden shadow-sm",
        @active_tab != :cart && "hidden lg:flex"
      ]}>
        <CatalogComponent.render_catalog
          categories={@categories}
          selected_category_id={@selected_category_id}
          search_query={@search_query}
          cart={@cart}
          mobile_cart_expanded={@mobile_cart_expanded}
        />
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
                <span class="badge badge-sm badge-primary ml-1 font-mono">{@cart.total_quantity}</span>
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
              <div class="flex justify-between items-center mb-3 pb-2 border-b border-base-200">
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
                <% end %>
              </div>
            <% end %>
          </div>

          <div class={[@active_tab != :details && "hidden lg:hidden"]}>
            <div class="lg:hidden mb-4 p-3 rounded-box bg-base-200/70 border border-base-300">
              <div class="flex justify-between items-center mb-2 pb-2 border-b border-base-300">
                <span class="font-bold text-xs uppercase text-base-content/60">{gettext(
                  "Selected Items"
                )} ({@cart.total_quantity})</span>
                <button
                  type="button"
                  phx-click="switch_tab"
                  phx-value-tab="cart"
                  class="btn btn-ghost btn-xs text-primary"
                >{gettext("Edit")}</button>
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

            <DetailsComponent.render_form form={@form} />
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
