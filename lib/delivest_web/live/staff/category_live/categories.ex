defmodule DelivestWeb.Staff.CategoryLive.Categories do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Net}
  alias Delivest.Net.Category

  on_mount {DelivestWeb.Hooks.Permission, "categories.read"}

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    categories =
      Net.list_staff_categories_for_branch(staff, branch_id)

    {:ok,
     socket
     |> assign(
       branch_id: branch_id,
       categories: categories,
       category: nil,
       category_to_delete: nil,
       ordering_category: nil,
       ordering_products: []
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    categories =
      if branch_id, do: Net.list_staff_categories_for_branch(staff, branch_id), else: []

    socket = assign(socket, categories: categories, ordering_category: nil, ordering_products: [])

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "categories.create") do
      assign(socket, page_title: gettext("Create category"), category: %Category{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create category."))
      |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/categories")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "categories.update") do
      case Net.get_branch_category(socket.assigns.branch_id, id) do
        {:ok, category} ->
          assign(socket, page_title: gettext("Edit category"), category: category)

        _ ->
          push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/categories")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit category."))
      |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/categories")
    end
  end

  defp apply_action(socket, :products, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "products.update") do
      case Net.get_branch_category(socket.assigns.branch_id, id) do
        {:ok, category} ->
          assign(socket,
            page_title: gettext("Products order"),
            category: nil,
            ordering_category: category,
            ordering_products: Net.list_category_products(socket.assigns.branch_id, category.id)
          )

        _ ->
          push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/categories")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit products."))
      |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/categories")
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Categories"), category: nil)
  end

  @impl true
  def handle_event(
        "reorder_category",
        %{"id" => id, "above_order" => above_order, "below_order" => below_order},
        socket
      ) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    with {:ok, category} <- Net.get_branch_category(socket.assigns.branch_id, id),
         {:ok, _updated} <- Net.update_category_order(staff, category, above_order, below_order) do
      categories = Net.list_staff_categories_for_branch(staff, branch_id)
      {:noreply, assign(socket, categories: categories)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to reorder category"))}
    end
  end

  @impl true
  def handle_event(
        "reorder_product",
        %{"id" => id, "above_order" => above_order, "below_order" => below_order},
        %{assigns: %{ordering_category: %Category{} = category}} = socket
      ) do
    %{current_staff: staff, branch_id: branch_id} = socket.assigns

    with %Net.Product{} = product <-
           Enum.find(socket.assigns.ordering_products, &(&1.id == id)),
         {:ok, _updated} <- Net.update_product_order(staff, product, above_order, below_order) do
      {:noreply,
       assign(socket, ordering_products: Net.list_category_products(branch_id, category.id))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to reorder product"))}
    end
  end

  def handle_event("reorder_product", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "categories.delete") do
      case Net.get_branch_category(socket.assigns.branch_id, id) do
        {:ok, category} -> {:noreply, assign(socket, category_to_delete: category)}
        _ -> {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  @impl true
  def handle_event(
        "confirm_delete",
        _,
        %{assigns: %{category_to_delete: category, branch_id: branch_id} = assigns} = socket
      ) do
    case Net.delete_category(assigns.current_staff, category) do
      {:ok, _} ->
        categories = Net.list_category_for_branch(branch_id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Category deleted"))
         |> assign(categories: categories, category_to_delete: nil)}

      _ ->
        {:noreply,
         socket |> put_flash(:error, gettext("Delete failed")) |> assign(category_to_delete: nil)}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, category_to_delete: nil)}
  end

  @impl true
  def handle_info(
        {DelivestWeb.Staff.CategoryLive.CategoryFormComponent, {:saved, _category}},
        socket
      ) do
    branch_id = socket.assigns.branch_id

    # Перезагружаем актуальный отсортированный список категорий
    categories = Net.list_staff_categories_for_branch(socket.assigns.current_staff, branch_id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Category saved successfully"))
     |> assign(categories: categories)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-4xl mx-auto">
      <.page_header
        title={gettext("Categories Management")}
        subtitle={gettext("Drag and drop items to reorder menu categories")}
      >
        <:actions>
          <.link
            :if={Identity.can?(@current_staff, "categories.create")}
            patch={~p"/staff/b/#{@current_branch}/categories/new"}
            class="btn btn-primary"
          >
            {gettext("Create Category")}
          </.link>
        </:actions>
      </.page_header>

      <div id="categories-list" phx-hook="SortableCategories" class="space-y-2">
        <%= for category <- @categories do %>
          <div
            class="flex items-center justify-between p-4 bg-base-100 shadow rounded-lg border border-base-200 cursor-default"
            data-id={category.id}
            data-order={category.order}
          >
            <div class="flex items-center gap-3">
              <span class="drag-handle cursor-grab hover:text-primary text-base-content/50 p-1">
                <.icon name="hero-bars-3" class="w-5 h-5" />
              </span>
              <span class="font-medium text-lg">{category.name}</span>
            </div>

            <div class="flex items-center gap-1">
              <.link
                :if={Identity.can?(@current_staff, "products.update")}
                patch={~p"/staff/b/#{@current_branch}/categories/#{category.id}/products"}
                class="btn btn-sm btn-ghost btn-square"
                title={gettext("Products order")}
              >
                <.icon name="hero-queue-list" class="w-5 h-5" />
              </.link>

              <.link
                :if={Identity.can?(@current_staff, "categories.update")}
                patch={~p"/staff/b/#{@current_branch}/categories/#{category.id}/edit"}
                class="btn btn-sm btn-ghost btn-square text-info"
                title={gettext("Edit")}
              >
                <.icon name="hero-pencil-square" class="w-5 h-5" />
              </.link>

              <button
                :if={Identity.can?(@current_staff, "categories.delete")}
                type="button"
                phx-click="delete_click"
                phx-value-id={category.id}
                class="btn btn-sm btn-ghost btn-square text-error"
                title={gettext("Delete")}
              >
                <.icon name="hero-trash" class="w-5 h-5" />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <.slide_over
        id="category-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/b/#{@current_branch}/categories")}
      >
        <.live_component
          :if={@category}
          module={DelivestWeb.Staff.CategoryLive.CategoryFormComponent}
          id={@category.id || :new}
          action={@live_action}
          category={@category}
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/b/#{@current_branch}/categories"}
        />
      </.slide_over>

      <.slide_over
        id="category-products-slideover"
        show={@live_action == :products}
        title={@ordering_category && @ordering_category.name}
        on_close={JS.patch(~p"/staff/b/#{@current_branch}/categories")}
      >
        <p class="text-sm text-base-content/60 mb-4">
          {gettext("Drag products to set the order they appear in the menu.")}
        </p>

        <p :if={@ordering_category && @ordering_products == []} class="text-sm opacity-60">
          {gettext("No products in this category yet.")}
        </p>

        <div
          :if={@ordering_category && @ordering_products != []}
          id={"category-products-#{@ordering_category.id}"}
          phx-hook="SortableProducts"
          class="space-y-2"
        >
          <div
            :for={product <- @ordering_products}
            id={"ordered-product-#{product.id}"}
            class="flex items-center gap-3 p-3 bg-base-100 rounded-lg border border-base-200"
            data-id={product.id}
            data-order={product.order}
          >
            <span class="drag-handle cursor-grab hover:text-primary text-base-content/50 p-1">
              <.icon name="hero-bars-3" class="w-5 h-5" />
            </span>
            <img
              :if={product.media}
              src={Delivest.Media.thumb_url_from_file(product.media)}
              class="size-10 rounded object-cover shrink-0"
              alt=""
            />
            <div
              :if={!product.media}
              class="size-10 rounded bg-base-200 shrink-0 flex items-center justify-center"
            >
              <.icon name="hero-photo" class="size-5 opacity-40" />
            </div>
            <div class="min-w-0 flex-1">
              <div class="font-medium truncate">{product.name}</div>
              <div class="text-sm font-mono opacity-60">{product.price}</div>
            </div>
            <span :if={!product.is_active} class="badge badge-ghost badge-sm whitespace-nowrap">
              {gettext("Inactive")}
            </span>
          </div>
        </div>
      </.slide_over>

      <.modal
        id="delete-modal"
        show={@category_to_delete != nil}
        title={gettext("Delete Category")}
        description={gettext("Are you sure you want to delete this category?")}
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
