defmodule DelivestWeb.Staff.OrderLive.OrderForm do
  use DelivestWeb, :live_view

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Net.Catalogs
  alias Delivest.Oms
  alias Delivest.Oms.Order
  alias DelivestWeb.Staff.OrderLive.{OrderDraft, SaveErrors}

  alias DelivestWeb.Staff.OrderLive.Components.{
    CartComponent,
    CatalogComponent,
    DetailsComponent,
    FooterComponent,
    TabsComponent
  }

  on_mount {DelivestWeb.Hooks.Permission, "orders.create"}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    case OrderDraft.fetch_editable(staff, branch.id, id) do
      {:ok, order} ->
        {:ok, init(socket, OrderDraft.edit(order, connected?(socket)))}

      {:error, message} ->
        {:ok, socket |> put_flash(:error, message) |> redirect(to: ~p"/staff/orders")}
    end
  end

  def mount(_params, _session, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns
    {:ok, init(socket, OrderDraft.new(staff, branch.id))}
  end

  defp init(socket, %{order: order, cart: cart, title: title}) do
    branch_id = socket.assigns.current_branch.id
    {:ok, categories} = Catalogs.get_menu_for_branch(branch_id)

    assign(socket,
      order: order,
      is_edit: order.id != nil,
      page_title: title,
      branch_id: branch_id,
      cart: cart,
      categories: categories,
      selected_category_id: nil,
      search_query: "",
      active_tab: :cart,
      mobile_cart_expanded: false,
      form: to_form(Order.changeset(order, %{}))
    )
  end

  @impl true
  def handle_event("detach_cart", _params, socket) do
    case Oms.clear_cart(socket.assigns.cart.id) do
      {:ok, cart} ->
        {:noreply,
         socket |> assign(cart: cart) |> put_flash(:info, gettext("Cart has been cleared"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to clear cart"))}
    end
  end

  def handle_event("switch_tab", %{"tab" => "cart"}, socket),
    do: {:noreply, assign(socket, active_tab: :cart)}

  def handle_event("switch_tab", %{"tab" => "details"}, socket),
    do: {:noreply, assign(socket, active_tab: :details)}

  def handle_event("toggle_mobile_cart", _params, socket) do
    {:noreply, assign(socket, mobile_cart_expanded: !socket.assigns.mobile_cart_expanded)}
  end

  def handle_event("select_category", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_category_id: if(id == "", do: nil, else: id))}
  end

  def handle_event("search_products", %{"search" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  def handle_event("add_item", %{"product-id" => product_id}, socket) do
    case Oms.add_item(socket.assigns.cart.id, product_id) do
      {:ok, _item, cart} ->
        {:noreply, assign(socket, cart: cart)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add product to cart."))}
    end
  end

  def handle_event("remove_item", %{"product-id" => product_id}, socket) do
    socket.assigns.cart.id |> Oms.remove_item(product_id) |> assign_cart(socket)
  end

  def handle_event("delete_item", %{"product-id" => product_id}, socket) do
    socket.assigns.cart.id |> Oms.remove_item(product_id, all: true) |> assign_cart(socket)
  end

  def handle_event("validate_order", %{"order" => params}, socket) do
    changeset =
      socket.assigns.order
      |> Order.changeset(Map.put(params, "cart_id", socket.assigns.cart.id))
      |> Map.put(:action, :validate)
      |> validate_address()

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_order", %{"order" => params}, socket) do
    params
    |> Map.put("cart_id", socket.assigns.cart.id)
    |> save(socket)
    |> handle_saved(socket)
  end

  defp assign_cart({:ok, _status, cart}, socket), do: {:noreply, assign(socket, cart: cart)}
  defp assign_cart({:error, _reason}, socket), do: {:noreply, socket}

  defp validate_address(changeset) do
    case Ecto.Changeset.get_change(changeset, :address) do
      %Ecto.Changeset{} = address ->
        Ecto.Changeset.put_change(changeset, :address, %{address | action: :validate})

      _ ->
        changeset
    end
  end

  defp save(params, %{assigns: %{order: %Order{id: nil}} = assigns}) do
    params
    |> Map.put("branch_id", assigns.branch_id)
    |> Map.put("staff_id", assigns.current_staff.id)
    |> Oms.create_order()
  end

  defp save(params, %{assigns: %{order: order}}), do: Oms.update_order(order, params)

  defp handle_saved({:ok, _order}, socket) do
    message =
      if socket.assigns.is_edit,
        do: gettext("Order updated successfully"),
        else: gettext("Order created successfully")

    {:noreply, socket |> put_flash(:info, message) |> push_navigate(to: ~p"/staff/orders")}
  end

  defp handle_saved({:error, _step, %Ecto.Changeset{data: %Order{}} = changeset}, socket) do
    {:noreply,
     socket |> put_flash(:error, gettext("Validation error")) |> assign(form: to_form(changeset))}
  end

  defp handle_saved({:error, _step, reason}, socket), do: handle_saved({:error, reason}, socket)

  defp handle_saved({:error, reason}, socket),
    do: {:noreply, put_flash(socket, :error, SaveErrors.message(reason))}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full min-h-screen lg:min-h-0 lg:h-[calc(100vh-4rem)] flex flex-col lg:flex-row overflow-y-auto lg:overflow-hidden gap-3 bg-base-200 pb-20 lg:pb-0">
      <div class="lg:hidden shrink-0 bg-base-100 p-2 rounded-box border border-base-300 shadow-sm sticky top-0 z-20">
        <TabsComponent.render_tabs
          active_tab={@active_tab}
          quantity={@cart.total_quantity}
          cart_label={gettext("1. Menu & Cart")}
          details_label={gettext("2. Checkout")}
          compact
        />
      </div>

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
          <TabsComponent.render_tabs
            active_tab={@active_tab}
            quantity={@cart.total_quantity}
            cart_label={gettext("Cart")}
            details_label={gettext("Order Details")}
          />
        </div>

        <div class="flex-1 lg:overflow-y-auto p-3 lg:p-4">
          <div class={[@active_tab != :cart && "hidden"]}>
            <CartComponent.render_items cart={@cart} />
          </div>

          <div class={[@active_tab != :details && "hidden"]}>
            <CartComponent.render_summary cart={@cart} />
            <DetailsComponent.render_form form={@form} />
          </div>
        </div>

        <FooterComponent.render_footer cart={@cart} active_tab={@active_tab} is_edit={@is_edit} />
      </div>
    </div>
    """
  end
end
