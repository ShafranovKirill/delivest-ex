defmodule DelivestWeb.Staff.ProductLive.Products do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Repo, Net}
  alias Delivest.Net.Product
  alias DelivestWeb.Staff.ProductLive.ProductFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "product.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    {:ok,
     socket
     |> assign(product_to_delete: nil, branch_id: branch_id)
     |> stream(:products, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")
    branch_id = socket.assigns.branch_id

    flop_params =
      if search != "" do
        Map.put(params, "filters", %{
          "0" => %{"field" => "name", "op" => "ilike_and", "value" => search}
        })
      else
        params
      end

    case Net.Products.list_staff_products_for_branch(
           socket.assigns.current_staff,
           branch_id,
           flop_params,
           preload: [:category]
         ) do
      {:ok, {products, meta}} ->
        socket =
          socket
          |> assign(meta: meta, search: search)
          |> stream(:products, products, reset: true)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/products")}
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Products list"), product: nil)
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "products.create") do
      assign(socket, page_title: gettext("Create product"), product: %Product{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create products."))
      |> push_patch(to: ~p"/staff/products")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "products.update") do
      case Repo.get(Product, id) |> Repo.preload([:category]) do
        %Product{} = product ->
          assign(socket, page_title: gettext("Edit product"), product: product)

        _ ->
          push_patch(socket, to: ~p"/staff/products")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit products."))
      |> push_patch(to: ~p"/staff/products")
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = build_query_params(socket.assigns, %{"search" => search, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/products?#{params}")}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    params = build_query_params(socket.assigns, %{"page_size" => size, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/products?#{params}")}
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    if Identity.can?(socket.assigns.current_staff, "products.delete") do
      product = Repo.get(Product, id)
      {:noreply, assign(socket, product_to_delete: product)}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You don't have permission to delete products."))
       |> push_patch(to: ~p"/staff/products")}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{product_to_delete: product}} = socket) do
    case Net.Products.soft_delete_product(socket.assigns.current_staff, product) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Product deleted successfully"))
         |> stream_delete(:products, product)
         |> assign(product_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete product"))}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, product_to_delete: nil)}
  end

  @impl true
  def handle_info({ProductFormComponent, {:saved, product}}, socket) do
    product_with_assoc = Repo.preload(product, [:category])
    action = socket.assigns.live_action

    msg =
      case action do
        :new -> gettext("Product created successfully")
        :edit -> gettext("Product updated successfully")
        _ -> gettext("Product saved successfully")
      end

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> stream_insert(:products, product_with_assoc)
     |> push_patch(to: ~p"/staff/products?#{build_query_params(socket.assigns, %{})}")}
  end

  defp build_query_params(assigns, overrides) do
    meta = assigns.meta

    order_by =
      meta.flop.order_by
      |> List.wrap()
      |> Enum.map(&to_string/1)

    order_directions =
      meta.flop.order_directions
      |> List.wrap()
      |> Enum.map(&to_string/1)

    %{
      "search" => assigns.search,
      "page" => meta.current_page,
      "page_size" => meta.page_size,
      "order_by" => order_by,
      "order_directions" => order_directions
    }
    |> Map.merge(overrides)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" or v == [] end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Products")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Manage branch products, prices, and categories.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.button
            :if={Identity.can?(@current_staff, "products.create")}
            patch={~p"/staff/products/new?#{build_query_params(assigns, %{})}"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="size-5" />
            {gettext("Create Product")}
          </.button>
        </div>
      </div>

      <div class="flex gap-4">
        <.form for={nil} phx-change="search" phx-submit="search" class="w-full max-w-sm">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-3 top-3.5 size-5 text-base-content/50 z-10"
            />
            <.input
              type="text"
              name="search"
              value={@search}
              placeholder={gettext("Search products...")}
              class="input input-bordered w-full pl-10"
              phx-debounce="500"
            />
          </div>
        </.form>
      </div>

      <% path_fn = fn overrides -> ~p"/staff/products?#{build_query_params(assigns, overrides)}" end %>

      <.table id="products" rows={@streams.products} meta={@meta} path_fn={path_fn}>
        <:col :let={{_id, prod}} label={gettext("Name")} sort="name">
          <span class="font-bold">{prod.name}</span>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Category")}>
          <span class="badge badge-ghost">{(prod.category && prod.category.name) || "—"}</span>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Price")} sort="price">
          <span class="font-mono">{prod.price}</span>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Description")}>
          <p class="max-w-xs truncate text-sm text-base-content/70" title={prod.description}>
            {prod.description || "—"}
          </p>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Status")}>
          <%= if prod.is_active do %>
            <span class="badge badge-success badge-sm whitespace-nowrap">{gettext("Active")}</span>
          <% else %>
            <span class="badge badge-error badge-sm text-error-content whitespace-nowrap">{gettext(
              "Inactive"
            )}</span>
          <% end %>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Media")}>
          <%= if prod.media_id do %>
            <span class="text-xs text-info font-medium">{gettext("Has photo")}</span>
          <% else %>
            <span class="text-xs opacity-40">—</span>
          <% end %>
        </:col>

        <:col :let={{_id, prod}} label={gettext("External ID")}>
          <%= if prod.external_id && prod.external_id != "" do %>
            <span class="text-xs badge badge-outline">{gettext("Specified")}</span>
          <% else %>
            <span class="text-xs opacity-40">—</span>
          <% end %>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Created At")} sort="inserted_at">
          <span class="text-sm opacity-60">{Calendar.strftime(prod.inserted_at, "%d.%m.%Y")}</span>
        </:col>

        <:action :let={{_id, prod}}>
          <div class="flex justify-end gap-2">
            <.button
              :if={Identity.can?(@current_staff, "products.update")}
              patch={~p"/staff/products/#{prod.id}/edit?#{build_query_params(assigns, %{})}"}
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              :if={Identity.can?(@current_staff, "products.delete")}
              phx-click="delete_click"
              phx-value-id={prod.id}
              class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </:action>
      </.table>

      <div class="flex justify-end">
        <.pagination meta={@meta} path_fn={path_fn} />
      </div>

      <.slide_over
        id="product-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/products?#{build_query_params(assigns, %{})}")}
      >
        <.live_component
          :if={@product}
          module={ProductFormComponent}
          id={@product.id || :new}
          action={@live_action}
          product={@product}
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/products?#{build_query_params(assigns, %{})}"}
        />
      </.slide_over>

      <.modal
        id="delete-product-modal"
        show={@product_to_delete != nil}
        title={gettext("Delete Product")}
        description={
          gettext(
            "Are you sure you want to delete this product? This action cannot be easily undone."
          )
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
