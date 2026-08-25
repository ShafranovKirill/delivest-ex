defmodule DelivestWeb.Staff.ProductLive.Products do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Repo, Net}
  alias Delivest.Net.Product
  alias Delivest.Net.Category
  alias DelivestWeb.Staff.ProductLive.ProductFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "product.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    categories = Repo.all(Category)

    {:ok,
     socket
     |> assign(
       product_to_delete: nil,
       branch_id: branch_id,
       categories: categories,
       search: "",
       selected_category_id: nil,
       selected_status: nil
     )
     |> stream(:products, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    branch_id = socket.assigns.branch_id
    flop_params = prepare_flop_params(params)

    case Net.Products.list_staff_products_for_branch(
           socket.assigns.current_staff,
           branch_id,
           flop_params,
           preload: [:category]
         ) do
      {:ok, {products, meta}} ->
        socket =
          socket
          |> assign(
            meta: meta,
            search: Map.get(params, "search", ""),
            selected_category_id: Flop.Filter.get_value(meta.flop.filters, :category_id),
            selected_status: Flop.Filter.get_value(meta.flop.filters, :is_active)
          )
          |> stream(:products, products, reset: true)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/products")}
    end
  end

  defp prepare_flop_params(params) do
    case Map.get(params, "search") do
      val when val in [nil, ""] ->
        params

      val ->
        filters = Map.get(params, "filters", %{})
        next_idx = map_size(filters)

        new_filters =
          Map.put(filters, to_string(next_idx), %{
            "field" => "name",
            "op" => "ilike_and",
            "value" => val
          })

        Map.put(params, "filters", new_filters)
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
  def handle_event("filter", params, socket) do
    search = params["search"]
    category_id = params["category_id"]
    is_active = parse_boolean_status(params["is_active"])

    filters =
      []
      |> maybe_add_filter(:category_id, "==", category_id)
      |> maybe_add_filter(:is_active, "==", is_active)
      |> maybe_add_filter(:name, "ilike_and", search)
      |> map_to_flop_format()

    query_params =
      build_query_params(socket.assigns, %{
        "search" => search,
        "filters" => filters,
        "page" => 1
      })

    {:noreply, push_patch(socket, to: ~p"/staff/products?#{query_params}")}
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
  def handle_event("cancel_media_upload", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: false)}
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

  @impl true
  def handle_info({ProductFormComponent, {:open_upload_modal}}, socket) do
    {:noreply, assign(socket, show_upload_modal: true)}
  end

  @impl true
  def handle_info(
        {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, results}},
        socket
      ) do
    handle_media_results(results, socket)
  end

  @impl true
  def handle_info(
        {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, _context_or_id, _type, results}},
        socket
      ) do
    handle_media_results(results, socket)
  end

  defp handle_media_results(results, socket) do
    {successes, _errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    media_file =
      case List.first(successes) do
        {:ok, file} -> file
        _ -> nil
      end

    if media_file do
      form_component_id = (socket.assigns.product && socket.assigns.product.id) || :new

      send_update(ProductFormComponent,
        id: form_component_id,
        uploaded_media: media_file
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, gettext("Image uploaded successfully"))
     |> assign(:show_upload_modal, false)}
  end

  defp maybe_add_filter(filters, _field, _op, val) when val in [nil, ""], do: filters

  defp maybe_add_filter(filters, field, op, val) do
    [%{"field" => to_string(field), "op" => op, "value" => val} | filters]
  end

  defp map_to_flop_format(list_of_filters) do
    list_of_filters
    |> Enum.with_index()
    |> Map.new(fn {filter, idx} -> {to_string(idx), filter} end)
  end

  defp parse_boolean_status("true"), do: true
  defp parse_boolean_status("false"), do: false
  defp parse_boolean_status(_), do: nil

  defp with_indexed_map(list) do
    list
    |> Enum.map(fn
      %Flop.Filter{} = f -> Map.from_struct(f)
      f -> f
    end)
    |> Enum.with_index()
    |> Map.new(fn {f, idx} -> {to_string(idx), f} end)
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

    filters_for_query =
      meta.flop.filters
      |> List.wrap()
      |> Enum.map(fn
        %Flop.Filter{} = f -> Map.from_struct(f)
        f -> f
      end)
      |> with_indexed_map()

    %{
      "search" => assigns.search,
      "page" => meta.current_page,
      "page_size" => meta.page_size,
      "order_by" => order_by,
      "order_directions" => order_directions,
      "filters" => filters_for_query
    }
    |> Map.merge(overrides)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" or v == [] or v == %{} end)
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

      <.form
        for={nil}
        phx-change="filter"
        class="flex gap-4 items-center justify-between flex-wrap w-full"
      >
        <div class="relative w-full sm:max-w-sm">
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

        <div class="flex items-center gap-3 flex-wrap sm:flex-nowrap">
          <select name="category_id" class="select select-bordered w-full sm:w-52 shrink-0">
            <option value="">{gettext("All categories")}</option>
            <%= for cat <- @categories do %>
              <option value={cat.id} selected={@selected_category_id == cat.id}>{cat.name}</option>
            <% end %>
          </select>

          <select name="is_active" class="select select-bordered w-full sm:w-48 shrink-0">
            <option value="">{gettext("All statuses")}</option>
            <option value="true" selected={@selected_status == true}>{gettext("Active")}</option>
            <option value="false" selected={@selected_status == false}>{gettext("Inactive")}</option>
          </select>
        </div>
      </.form>

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

        <:col :let={{_id, prod}} label={gettext("Status")}>
          <%= if prod.is_active do %>
            <span class="badge badge-success badge-sm whitespace-nowrap">{gettext("Active")}</span>
          <% else %>
            <span class="badge badge-error badge-sm text-error-content whitespace-nowrap">{gettext(
              "Inactive"
            )}</span>
          <% end %>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Description")}>
          <%= if prod.description && prod.description != "" do %>
            <span class="text-xs badge badge-outline">{gettext("Specified")}</span>
          <% else %>
            <span class="text-xs opacity-40">—</span>
          <% end %>
        </:col>

        <:col :let={{_id, prod}} label={gettext("Media")}>
          <%= if prod.media_id do %>
            <span class="text-xs badge badge-outline whitespace-nowrap">{gettext("Has photo")}</span>
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

      <%= if assigns[:show_upload_modal] do %>
        <.live_component
          module={DelivestWeb.StudioLive.MediaUploadComponent}
          id="product-media-upload"
          current_staff={@current_staff}
          media_group_name={@current_branch.id}
          upload_type="image"
          context="product"
        />
      <% end %>

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
