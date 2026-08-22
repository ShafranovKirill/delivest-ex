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
       category_to_delete: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    categories =
      if branch_id, do: Net.list_staff_categories_for_branch(staff, branch_id), else: []

    socket = assign(socket, categories: categories)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "categories.create") do
      assign(socket, page_title: gettext("Create category"), category: %Category{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create category."))
      |> push_patch(to: ~p"/staff/categories")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "categories.update") do
      case Net.get_category(id) do
        {:ok, category} ->
          assign(socket, page_title: gettext("Edit category"), category: category)

        _ ->
          push_patch(socket, to: ~p"/staff/categories")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit category."))
      |> push_patch(to: ~p"/staff/categories")
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

    with {:ok, category} <- Net.get_category(id),
         {:ok, _updated} <- Net.update_category_order(staff, category, above_order, below_order) do
      categories = Net.list_category_for_branch(branch_id)
      {:noreply, assign(socket, categories: categories)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to reorder category"))}
    end
  end

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "categories.delete") do
      case Net.get_category(id) do
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
    <div class="space-y-6 p-6 max-w-4xl mx-auto">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold">{gettext("Categories Management")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Drag and drop items to reorder menu categories")}
          </p>
        </div>

        <.link
          :if={Identity.can?(@current_staff, "categories.create")}
          patch={~p"/staff/categories/new"}
          class="btn btn-primary"
        >
          {gettext("Create Category")}
        </.link>
      </div>

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
                :if={Identity.can?(@current_staff, "categories.update")}
                patch={~p"/staff/categories/#{category.id}/edit"}
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
        on_close={JS.patch(~p"/staff/categories")}
      >
        <.live_component
          :if={@category}
          module={DelivestWeb.Staff.CategoryLive.CategoryFormComponent}
          id={@category.id || :new}
          action={@live_action}
          category={@category}
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/categories"}
        />
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
