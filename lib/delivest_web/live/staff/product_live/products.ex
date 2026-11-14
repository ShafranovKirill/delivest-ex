defmodule DelivestWeb.Staff.ProductLive.Products do
  use DelivestWeb, :live_view

  alias Delivest.{Gateway, Identity, Money, Repo, Net}
  alias Delivest.Net.{Product, ProductCrmIds, Stops}
  alias DelivestWeb.Staff.ProductLive.ProductFormComponent

  import DelivestWeb.Staff.ProductLive.StopControl, only: [stop_control: 1]
  import DelivestWeb.Staff.FoundationComponents, only: [filter_bar: 1]

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    categories = Net.list_branch_categories(branch_id)

    if connected?(socket) and branch_id do
      Delivest.Net.Products.subscribe_branch(branch_id)
    end

    {:ok,
     socket
     |> assign(
       product_to_delete: nil,
       branch_id: branch_id,
       categories: categories,
       search: "",
       selected_category_id: nil,
       selected_status: nil,
       selected_ids: [],
       bulk_delete_open: false,
       form_version: 0,
       crm_menu: Gateway.crm?(socket.assigns.current_branch, :menu),
       stops: Stops.by_product(branch_id),
       stopped_filter: false,
       params: %{}
     )
     |> stream(:products, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    branch_id = socket.assigns.branch_id
    flop_params = prepare_flop_params(params)
    stopped_filter = params["stopped"] == "true"

    case Net.list_staff_products_for_branch(
           socket.assigns.current_staff,
           branch_id,
           flop_params,
           preload: [:category, :external_ids],
           only_ids: if(stopped_filter, do: MapSet.to_list(Stops.stopped_ids(branch_id)))
         ) do
      {:ok, {products, meta}} ->
        socket =
          socket
          |> assign(
            params: params,
            stopped_filter: stopped_filter,
            meta: meta,
            page_product_ids: MapSet.new(Enum.map(products, & &1.id)),
            selected_ids: [],
            search: Map.get(params, "search", ""),
            selected_category_id: Flop.Filter.get_value(meta.flop.filters, :category_id),
            selected_status: Flop.Filter.get_value(meta.flop.filters, :is_active)
          )
          |> stream(:products, products, reset: true)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/products")}
    end
  end

  defp prepare_flop_params(params) do
    params = Map.put_new(params, "page_size", 25)

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
    if Identity.can?(socket.assigns.current_staff, "products.create") and
         not socket.assigns.crm_menu do
      assign(socket, page_title: gettext("Create product"), product: %Product{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create products."))
      |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/products")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "products.update") do
      case Net.get_branch_product(socket.assigns.branch_id, id,
             preload: [:category, :external_ids]
           ) do
        {:ok, product} ->
          assign(socket,
            page_title: gettext("Edit product"),
            product: ProductCrmIds.load(product, socket.assigns.current_branch.id)
          )

        _ ->
          push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/products")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit products."))
      |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/products")
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case Net.get_branch_product(socket.assigns.branch_id, id, preload: [:category, :external_ids]) do
      {:ok, product} ->
        assign(socket,
          page_title: product.name,
          product: ProductCrmIds.load(product, socket.assigns.branch_id)
        )

      _ ->
        push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/products")
    end
  end

  @impl true
  def handle_event("select_products", params, socket) do
    ids =
      if Identity.can?(socket.assigns.current_staff, "products.delete") and
           not socket.assigns.crm_menu do
        params
        |> Map.get("ids", [])
        |> Enum.uniq()
        |> Enum.filter(&MapSet.member?(socket.assigns.page_product_ids, &1))
      else
        []
      end

    {:noreply, assign(socket, selected_ids: ids)}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, selected_ids: [])}

  def handle_event("filter", params, socket) do
    search = params["search"]
    category_id = params["category_id"]
    is_active = parse_boolean_status(params["is_active"])
    stopped = if params["is_active"] == "stopped", do: "true"

    filters =
      []
      |> maybe_add_filter(:category_id, "==", category_id)
      |> maybe_add_filter(:is_active, "==", is_active)
      |> map_to_flop_format()

    query_params =
      build_query_params(socket.assigns, %{
        "search" => search,
        "filters" => filters,
        "stopped" => stopped,
        "page" => 1
      })

    {:noreply,
     push_patch(socket,
       to: ~p"/staff/b/#{socket.assigns.current_branch}/products?#{query_params}"
     )}
  end

  def handle_event("stop", %{"id" => id, "period" => period}, socket)
      when period in ~w(today until_resumed) do
    with_branch_product(socket, id, fn product ->
      Stops.stop(
        Identity.fresh_staff(socket.assigns.current_staff),
        socket.assigns.branch_id,
        product,
        String.to_existing_atom(period)
      )
    end)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    with_branch_product(socket, id, fn product ->
      Stops.resume(
        Identity.fresh_staff(socket.assigns.current_staff),
        socket.assigns.branch_id,
        product
      )
    end)
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    params = build_query_params(socket.assigns, %{"page_size" => size, "page" => 1})

    {:noreply,
     push_patch(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/products?#{params}")}
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    with true <- Identity.can?(socket.assigns.current_staff, "products.delete"),
         false <- socket.assigns.crm_menu,
         {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id) do
      {:noreply, assign(socket, product_to_delete: product)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You don't have permission to delete products."))
         |> push_patch(to: ~p"/staff/b/#{socket.assigns.current_branch}/products")}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{crm_menu: true}} = socket) do
    {:noreply, assign(socket, product_to_delete: nil)}
  end

  def handle_event("confirm_delete", _, %{assigns: %{product_to_delete: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_delete", _, %{assigns: %{product_to_delete: product}} = socket) do
    case Net.soft_delete_product(Identity.fresh_staff(socket.assigns.current_staff), product) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Product deleted successfully"))
         |> assign(product_to_delete: nil)
         |> push_patch(
           to:
             ~p"/staff/b/#{socket.assigns.current_branch}/products?#{build_query_params(socket.assigns, %{})}"
         )}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete product"))}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, product_to_delete: nil)}
  end

  def handle_event("bulk_delete_click", _, socket) do
    {:noreply,
     assign(socket,
       bulk_delete_open:
         socket.assigns.selected_ids != [] and not socket.assigns.crm_menu and
           Identity.can?(socket.assigns.current_staff, "products.delete")
     )}
  end

  def handle_event("cancel_bulk_delete", _, socket) do
    {:noreply, assign(socket, bulk_delete_open: false)}
  end

  def handle_event("confirm_bulk_delete", _, %{assigns: %{crm_menu: true}} = socket) do
    {:noreply, assign(socket, bulk_delete_open: false)}
  end

  def handle_event("confirm_bulk_delete", _, socket) do
    %{branch_id: branch_id, selected_ids: ids} = socket.assigns
    staff = Identity.fresh_staff(socket.assigns.current_staff)
    ids = Enum.filter(ids, &MapSet.member?(socket.assigns.page_product_ids, &1))

    case Net.soft_delete_products(staff, branch_id, ids) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> assign(selected_ids: [], bulk_delete_open: false)
         |> put_flash(
           :info,
           gettext("Products deleted: %{count}; failed: %{failed}",
             count: length(deleted),
             failed: length(ids) - length(deleted)
           )
         )
         |> push_patch(
           to:
             ~p"/staff/b/#{socket.assigns.current_branch}/products?#{build_query_params(socket.assigns, %{})}"
         )}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(bulk_delete_open: false)
         |> put_flash(:error, gettext("You don't have permission to delete products."))}
    end
  end

  @impl true
  def handle_event("cancel_media_upload", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: false)}
  end

  @impl true
  def handle_info({ProductFormComponent, {:saved, product}}, socket) do
    action = socket.assigns.live_action

    msg =
      case action do
        :new -> gettext("Product created successfully")
        :edit -> gettext("Product updated successfully")
        _ -> gettext("Product saved successfully")
      end

    socket = put_flash(socket, :info, msg)

    if action == :new do
      {:noreply, push_patch(socket, to: product_list_path(socket.assigns))}
    else
      {:noreply, push_navigate(socket, to: product_list_path(socket.assigns, product.id))}
    end
  end

  @impl true
  def handle_info(
        {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, results}},
        socket
      ) do
    case Enum.find(results, &match?({:ok, _file}, &1)) do
      {:ok, media_file} ->
        send_update(ProductFormComponent,
          id: (socket.assigns[:product] && socket.assigns.product.id) || :new,
          uploaded_media: media_file
        )

        {:noreply,
         socket
         |> assign(show_upload_modal: false)
         |> put_flash(:info, gettext("Image uploaded successfully"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to upload image"))}
    end
  end

  @impl true
  def handle_info(:stops_changed, socket) do
    socket = assign(socket, stops: Stops.by_product(socket.assigns.branch_id))

    if socket.assigns.live_action == :edit,
      do: {:noreply, socket},
      else: handle_params(socket.assigns.params, nil, socket)
  end

  @impl true
  def handle_info(:catalog_changed, socket) do
    if socket.assigns.live_action == :edit,
      do: {:noreply, socket},
      else: handle_params(socket.assigns.params, nil, socket)
  end

  @impl true
  def handle_info({:product_created, product}, socket) do
    product_with_assoc = Repo.preload(product, [:category, :external_ids])
    {:noreply, stream_insert(socket, :products, product_with_assoc, at: 0)}
  end

  @impl true
  def handle_info({:product_updated, product}, socket) do
    product_with_assoc = Repo.preload(product, [:category, :external_ids])
    {:noreply, stream_insert(socket, :products, product_with_assoc)}
  end

  @impl true
  def handle_info({:product_deleted, product}, socket) do
    {:noreply, stream_delete(socket, :products, product)}
  end

  @impl true
  def handle_info({ProductFormComponent, {:open_upload_modal}}, socket) do
    {:noreply, assign(socket, show_upload_modal: true)}
  end

  @impl true
  def handle_info({ProductFormComponent, :reload_requested}, socket) do
    socket =
      socket
      |> apply_action(:edit, %{"id" => socket.assigns.product.id})
      |> assign(:form_version, socket.assigns.form_version + 1)

    {:noreply, socket}
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

  defp with_branch_product(socket, id, action) do
    with {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id),
         {:ok, _result} <- action.(product) do
      {:noreply, socket}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _error -> {:noreply, put_flash(socket, :error, gettext("Failed to update the stop list"))}
    end
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
      |> Enum.reject(fn filter ->
        filter.field == :name and filter.op == :ilike_and and filter.value == assigns.search
      end)
      |> Enum.map(fn
        %Flop.Filter{} = f -> Map.from_struct(f)
        f -> f
      end)
      |> with_indexed_map()

    overrides =
      if Map.has_key?(overrides, "order_by"), do: Map.put(overrides, "page", 1), else: overrides

    %{
      "search" => assigns.search,
      "page" => meta.current_page,
      "page_size" => meta.page_size,
      "order_by" => order_by,
      "order_directions" => order_directions,
      "filters" => filters_for_query,
      "stopped" => if(assigns.stopped_filter, do: "true")
    }
    |> Map.merge(overrides)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" or v == [] or v == %{} end)
    |> Map.new()
  end

  defp product_list_path(assigns, product_id \\ nil) do
    path = ~p"/staff/b/#{assigns.current_branch}/products?#{build_query_params(assigns, %{})}"
    if product_id, do: path <> "#product-row-#{product_id}", else: path
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={if @live_action in [:edit, :show], do: @page_title, else: gettext("Products")}
      title_in_header={false}
    >
      <:actions>
        <.link
          :if={@live_action in [:edit, :show]}
          id="product-back-to-list"
          navigate={product_list_path(assigns, @product.id)}
          class="btn btn-ghost"
        >{gettext("Back to products")}</.link>
        <button
          :if={@live_action == :edit}
          type="submit"
          form="product-form"
          class="btn btn-primary"
          data-staff-save="edit"
        >{gettext("Save")}</button>
        <.link
          :if={@live_action == :show and Identity.can?(@current_staff, "products.update")}
          id="product-edit-link"
          navigate={
            ~p"/staff/b/#{@current_branch}/products/#{@product.id}/edit?#{build_query_params(assigns, %{})}"
          }
          class="btn btn-primary"
        >{gettext("Edit")}</.link>
        <.button
          :if={
            @live_action not in [:edit, :show] and Identity.can?(@current_staff, "products.create") and
              not @crm_menu
          }
          id="create-product"
          patch={~p"/staff/b/#{@current_branch}/products/new?#{build_query_params(assigns, %{})}"}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="size-5" />
          {gettext("Create Product")}
        </.button>
        <details :if={@live_action not in [:edit, :show]} id="product-more-actions">
          <summary class="btn btn-ghost list-none cursor-pointer">
            <.icon name="hero-ellipsis-horizontal" class="size-5" />
            {gettext("More")}
          </summary>
          <div class="flex flex-col items-start gap-1 py-2">
            <.link
              id="product-operations-link"
              navigate={~p"/staff/b/#{@current_branch}/products/operations"}
              class="btn btn-ghost btn-sm justify-start"
            >{gettext("Product operations")}</.link>
            <.link
              :if={Identity.can?(@current_staff, "products.create") and not @crm_menu}
              id="bulk-add-products"
              navigate={~p"/staff/b/#{@current_branch}/products/bulk"}
              class="btn btn-ghost btn-sm justify-start"
            >{gettext("Bulk add")}</.link>
          </div>
        </details>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @live_action in [:edit, :show] do %>
        <div
          id="product-edit-page"
          class="mx-auto max-w-4xl rounded-box border border-base-300 bg-base-100"
        >
          <.live_component
            :if={@product}
            module={ProductFormComponent}
            id={@product.id}
            action={@live_action}
            readonly={@live_action == :show}
            product={@product}
            branch_id={@branch_id}
            current_branch={@current_branch}
            current_staff={@current_staff}
            form_version={@form_version}
            patch={product_list_path(assigns, @product.id)}
          />
        </div>
      <% else %>
        <.filter_bar
          id="products-filter-bar"
          form_id="products-filter"
          query={@search}
          query_name="search"
          query_placeholder={gettext("Search products...")}
          reset_path={~p"/staff/b/#{@current_branch}/products"}
          active={@selected_category_id != nil or @selected_status != nil or @stopped_filter}
        >
          <:filter>
            <div class="flex items-center gap-3 flex-wrap sm:flex-nowrap">
              <select name="category_id" class="select select-bordered w-full sm:w-52 shrink-0">
                <option value="">{gettext("All categories")}</option>
                <%= for cat <- @categories do %>
                  <option value={cat.id} selected={@selected_category_id == cat.id}>
                    {cat.name}
                  </option>
                <% end %>
              </select>

              <select name="is_active" class="select select-bordered w-full sm:w-48 shrink-0">
                <option value="">{gettext("All statuses")}</option>
                <option value="true" selected={@selected_status == true}>{gettext("Active")}</option>
                <option value="false" selected={@selected_status == false}>
                  {gettext("Inactive")}
                </option>
                <option value="stopped" selected={@stopped_filter}>{gettext("In stop list")}</option>
              </select>
            </div>
          </:filter>
        </.filter_bar>

        <% path_fn = fn overrides ->
          ~p"/staff/b/#{@current_branch}/products?#{build_query_params(assigns, overrides)}"
        end %>

        <form id="product-selection" phx-change="select_products"></form>

        <.table
          id="products"
          rows={@streams.products}
          meta={@meta}
          path_fn={path_fn}
          staff_id={to_string(@current_staff.id)}
          list_id="products"
        >
          <:col
            :let={{_id, prod}}
            :if={Identity.can?(@current_staff, "products.delete") and not @crm_menu}
            label=""
          >
            <input
              type="checkbox"
              name="ids[]"
              value={prod.id}
              form="product-selection"
              class="checkbox checkbox-sm"
              aria-label={gettext("Select %{name}", name: prod.name)}
            />
          </:col>

          <:col :let={{_id, prod}} label={gettext("Name")} sort="name">
            <.link
              id={"product-row-#{prod.id}"}
              navigate={
                ~p"/staff/b/#{@current_branch}/products/#{prod.id}?#{build_query_params(assigns, %{})}"
              }
              class="font-bold hover:underline scroll-mt-24"
            >{prod.name}</.link>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Category")}>
            <span class="badge badge-ghost">{(prod.category && prod.category.name) || "—"}</span>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Price")} sort="price">
            <div class="font-mono">{Money.format(prod.price)}</div>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Quantity")} secondary>
            <span class="font-mono">
              <%= if prod.quantity do %>
                {prod.quantity} {gettext("pcs")}
              <% else %>
                —
              <% end %>
            </span>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Weight")} secondary>
            <span class="font-mono">
              <%= if prod.weight do %>
                {prod.weight} {if prod.measure_unit == :ml, do: gettext("ml"), else: gettext("g")}
              <% else %>
                —
              <% end %>
            </span>
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

          <:col :let={{_id, prod}} label={gettext("Stop list")}>
            <.stop_control
              product={prod}
              stops={Map.get(@stops, prod.id, [])}
              can_edit={Identity.can?(@current_staff, "stops.update")}
            />
          </:col>

          <:col :let={{_id, prod}} label={gettext("Description")} secondary>
            <%= if prod.description && prod.description != "" do %>
              <span class="text-xs badge badge-outline">{gettext("Specified")}</span>
            <% else %>
              <span class="text-xs opacity-40">—</span>
            <% end %>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Media")} secondary>
            <%= if prod.media_id do %>
              <span class="text-xs badge badge-outline whitespace-nowrap">{gettext("Has photo")}</span>
            <% else %>
              <span class="text-xs opacity-40">—</span>
            <% end %>
          </:col>

          <:col :let={{_id, prod}} label={gettext("External ID")} secondary>
            <%= if prod.external_ids != [] do %>
              <span class="text-xs badge badge-outline">{gettext("Specified")}</span>
            <% else %>
              <span class="text-xs opacity-40">—</span>
            <% end %>
          </:col>

          <:col :let={{_id, prod}} label={gettext("Created At")} sort="inserted_at" secondary>
            <span class="text-sm opacity-60">{Calendar.strftime(prod.inserted_at, "%d.%m.%Y")}</span>
          </:col>

          <:action :let={{_id, prod}}>
            <details
              :if={
                Identity.can?(@current_staff, "products.update") or
                  (Identity.can?(@current_staff, "products.delete") and not @crm_menu)
              }
              id={"product-row-more-#{prod.id}"}
              class="inline-block text-left"
            >
              <summary
                class="btn btn-ghost btn-xs list-none cursor-pointer"
                aria-label={gettext("More actions for %{name}", name: prod.name)}
              >
                {gettext("More")}
              </summary>
              <div class="flex flex-col items-start gap-1 py-1">
                <.link
                  :if={Identity.can?(@current_staff, "products.update")}
                  navigate={
                    ~p"/staff/b/#{@current_branch}/products/#{prod.id}/edit?#{build_query_params(assigns, %{})}"
                  }
                  class="btn btn-ghost btn-xs justify-start"
                >{gettext("Edit")}</.link>
                <button
                  :if={Identity.can?(@current_staff, "products.delete") and not @crm_menu}
                  type="button"
                  phx-click="delete_click"
                  phx-value-id={prod.id}
                  class="btn btn-ghost btn-xs justify-start text-error hover:bg-error/10"
                >{gettext("Delete")}</button>
              </div>
            </details>
          </:action>
        </.table>

        <div class="flex justify-end">
          <.pagination meta={@meta} path_fn={path_fn} page_sizes={[25, 50, 100]} />
        </div>

        <.selection_bar
          count={length(@selected_ids)}
          form="product-selection"
          on_clear={JS.push("clear_selection")}
        >
          <.link
            :if={Identity.can?(@current_staff, "products.create")}
            navigate={~p"/staff/b/#{@current_branch}/products/operations?#{[ids: @selected_ids]}"}
            class="btn btn-ghost btn-sm"
          >Копировать выбранные</.link>
          <.button
            :if={Identity.can?(@current_staff, "products.delete") and not @crm_menu}
            phx-click="bulk_delete_click"
            class="btn btn-ghost btn-sm text-error hover:bg-error/10"
          >
            <.icon name="hero-trash" class="size-4" />
            {gettext("Delete")}
          </.button>
        </.selection_bar>

        <.slide_over
          id="product-slideover"
          show={@live_action == :new}
          title={@page_title}
          on_close={
            JS.patch(~p"/staff/b/#{@current_branch}/products?#{build_query_params(assigns, %{})}")
          }
        >
          <.live_component
            :if={@live_action == :new and @product}
            module={ProductFormComponent}
            id={@product.id || :new}
            action={@live_action}
            readonly={false}
            product={@product}
            branch_id={@branch_id}
            current_branch={@current_branch}
            current_staff={@current_staff}
            form_version={@form_version}
            patch={~p"/staff/b/#{@current_branch}/products?#{build_query_params(assigns, %{})}"}
          />
        </.slide_over>
      <% end %>

      <%= if assigns[:show_upload_modal] do %>
        <.live_component
          module={DelivestWeb.StudioLive.MediaUploadComponent}
          id="product-media-upload"
          user_id={@current_staff.id}
          media_group_name={@current_branch.id}
          upload_type="image"
          context="product"
          is_private={false}
        />
      <% end %>

      <.modal
        id="delete-product-modal"
        show={@product_to_delete != nil}
        title={gettext("Delete Product")}
        description={
          gettext(
            "Delete %{name}? Its category, tags, modifiers and other linked settings will no longer appear with this product. This action cannot be easily undone.",
            name: @product_to_delete && @product_to_delete.name
          )
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />

      <.modal
        id="bulk-delete-products-modal"
        show={@bulk_delete_open}
        title={gettext("Delete selected products")}
        description={
          gettext("Delete %{count} selected products? This action cannot be easily undone.",
            count: length(@selected_ids)
          )
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_bulk_delete")}
        on_confirm={JS.push("confirm_bulk_delete")}
      />
    </div>
    """
  end
end
