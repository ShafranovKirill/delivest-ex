defmodule DelivestWeb.Staff.ProductLive.StopList do
  use DelivestWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Delivest.{Identity, Net}
  alias Delivest.Net.Stops
  alias DelivestWeb.Staff.ProductLive.BranchProducts

  import DelivestWeb.Staff.ProductLive.StopControl, only: [stop_control: 1]
  import DelivestWeb.Staff.FoundationComponents, only: [filter_bar: 1]

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    if connected?(socket), do: Net.Products.subscribe_branch(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Stop list"),
       branch_id: branch_id,
       categories: Net.list_branch_categories(branch_id),
       params: %{},
       search: "",
       category_id: "",
       picker_products: [],
       picker_open: false,
       can_edit: Identity.can?(socket.assigns.current_staff, "stops.update")
     )
     |> stream_configure(:stopped_products, dom_id: &"stop-list-#{&1.id}")
     |> stream(:stopped_products, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_page(socket, params)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    search = if is_binary(params["search"]), do: params["search"], else: ""
    category_id = if is_binary(params["category_id"]), do: params["category_id"], else: ""

    {:noreply,
     push_patch(socket,
       to:
         ~p"/staff/b/#{socket.assigns.current_branch}/products/stops?#{%{search: search, category_id: category_id}}"
     )}
  end

  def handle_event("open_picker", _, socket) do
    if socket.assigns.can_edit do
      {:noreply,
       assign(socket,
         picker_open: true,
         picker_products: BranchProducts.load(socket.assigns.branch_id)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket)
      when size in ~w(25 50 100) do
    {:noreply,
     push_patch(socket,
       to: stop_path(socket.assigns, %{"page_size" => size, "page" => 1})
     )}
  end

  def handle_event("update_page_size", _, socket), do: {:noreply, socket}

  def handle_event("stop", %{"id" => id, "period" => period}, socket)
      when period in ~w(today until_resumed) do
    with_product(socket, id, fn product ->
      Stops.stop(
        Identity.fresh_staff(socket.assigns.current_staff),
        socket.assigns.branch_id,
        product,
        String.to_existing_atom(period)
      )
    end)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    with_product(socket, id, fn product ->
      Stops.resume(
        Identity.fresh_staff(socket.assigns.current_staff),
        socket.assigns.branch_id,
        product
      )
    end)
  end

  @impl true
  def handle_info({:product_picker_cancelled, "stop-picker"}, socket),
    do: {:noreply, assign(socket, picker_open: false, picker_products: [])}

  def handle_info({:product_picker_confirmed, "stop-picker", ids}, socket) do
    branch_id = socket.assigns.branch_id
    staff = Identity.fresh_staff(socket.assigns.current_staff)
    products = BranchProducts.load(branch_id)
    by_id = Map.new(products, &{&1.id, &1})
    current = MapSet.new(Map.keys(Stops.by_product(branch_id)))
    added = Enum.reject(ids, &MapSet.member?(current, &1))
    removed = Enum.reject(MapSet.to_list(current), &(&1 in ids))

    result =
      with :ok <- Identity.authorize(staff, "stops.update", branch_id),
           true <- Enum.all?(ids, &Map.has_key?(by_id, &1)) do
        Delivest.Repo.transaction(fn ->
          Enum.each(added, fn id ->
            case Stops.stop(staff, branch_id, Map.fetch!(by_id, id), :until_resumed) do
              {:ok, _} -> :ok
              error -> Delivest.Repo.rollback(error)
            end
          end)

          Enum.each(removed, fn id ->
            case Stops.resume(staff, branch_id, Map.fetch!(by_id, id)) do
              {:ok, _} -> :ok
              error -> Delivest.Repo.rollback(error)
            end
          end)
        end)
      else
        false -> {:error, :invalid_products}
        error -> error
      end

    case result do
      {:ok, _} -> {:noreply, socket |> assign(picker_open: false, picker_products: []) |> load()}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to update the stop list"))}
    end
  end

  def handle_info(:stops_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:catalog_changed, socket), do: {:noreply, load(socket)}
  def handle_info({event, _product}, socket) when is_atom(event), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp with_product(socket, id, action) do
    with {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id),
         {:ok, _result} <- action.(product) do
      {:noreply, load(socket)}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _error -> {:noreply, put_flash(socket, :error, gettext("Failed to update the stop list"))}
    end
  end

  defp load(socket) do
    load_page(socket, socket.assigns.params)
  end

  defp load_page(socket, params) do
    search = if is_binary(params["search"]), do: params["search"], else: ""
    category_id = if is_binary(params["category_id"]), do: params["category_id"], else: ""
    raw_page = if is_binary(params["page"]), do: params["page"], else: "1"

    page =
      case Integer.parse(raw_page) do
        {number, ""} when number > 0 -> number
        _ -> 1
      end

    size = if params["page_size"] in ~w(25 50 100), do: params["page_size"], else: 25
    stops = Stops.by_product(socket.assigns.branch_id)

    filters =
      [{:name, "ilike_and", search}, {:category_id, "==", category_id}]
      |> Enum.reject(fn {_, _, value} -> value == "" end)
      |> Enum.with_index()
      |> Map.new(fn {{field, op, value}, index} ->
        {to_string(index), %{"field" => to_string(field), "op" => op, "value" => value}}
      end)

    query = %{"page" => page, "page_size" => size, "filters" => filters}

    case Net.list_staff_products_for_branch(
           socket.assigns.current_staff,
           socket.assigns.branch_id,
           query,
           preload: [:category],
           only_ids: Map.keys(stops)
         ) do
      {:ok, {products, meta}} ->
        socket
        |> assign(
          params: params,
          search: search,
          category_id: category_id,
          stops: stops,
          meta: meta
        )
        |> stream(:stopped_products, products, reset: true)

      {:error, _} ->
        socket
        |> assign(
          params: %{},
          search: "",
          category_id: "",
          stops: stops,
          meta: %Flop.Meta{
            total_count: 0,
            total_pages: 0,
            current_page: 1,
            page_size: 25,
            flop: %Flop{}
          }
        )
        |> stream(:stopped_products, [], reset: true)
    end
  end

  defp stop_path(assigns, overrides) do
    params =
      %{
        "search" => assigns.search,
        "category_id" => assigns.category_id,
        "page" => assigns.meta.current_page,
        "page_size" => assigns.meta.page_size
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/staff/b/#{assigns.current_branch}/products/stops?#{params}"
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Stop list")}
      title_in_header={false}
    >
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.filter_bar
        id="stop-list-filter-bar"
        form_id="stop-list-filter"
        query={@search}
        query_name="search"
        query_placeholder={gettext("Search products...")}
        reset_path={~p"/staff/b/#{@current_branch}/products/stops"}
        active={@category_id != ""}
      >
        <:filter>
          <select name="category_id" class="select select-bordered">
            <option value="">{gettext("All categories")}</option>
            <option
              :for={category <- @categories}
              value={category.id}
              selected={@category_id == category.id}
            >
              {category.name}
            </option>
          </select>
        </:filter>
      </.filter_bar>
      <button
        :if={@can_edit}
        id="stop-add-products"
        type="button"
        class="btn btn-primary"
        phx-click={JS.push_focus() |> JS.push("open_picker")}
      >{gettext("Add products")}</button>

      <% path_fn = fn overrides -> stop_path(assigns, overrides) end %>
      <.table id="stop-list" rows={@streams.stopped_products} meta={@meta} path_fn={path_fn}>
        <:col :let={{_id, product}} label={gettext("Name")}>{product.name}</:col>
        <:col :let={{_id, product}} label={gettext("Category")}>
          {(product.category && product.category.name) || "—"}
        </:col>
        <:action :let={{_id, product}}>
          <.stop_control
            product={product}
            stops={Map.get(@stops, product.id, [])}
            can_edit={@can_edit}
          />
        </:action>
      </.table>
      <.empty_state
        :if={@meta.total_count == 0}
        title={
          if @search != "" or @category_id != "",
            do: gettext("No results"),
            else: gettext("No products")
        }
      />
      <.pagination meta={@meta} path_fn={path_fn} page_sizes={[25, 50, 100]} />
      <.live_component
        :if={@picker_open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="stop-picker"
        products={@picker_products}
        selected_ids={Map.keys(@stops)}
        title={gettext("Add products")}
        on_save={fn ids -> send(self(), {:product_picker_confirmed, "stop-picker", ids}) end}
        on_cancel={fn -> send(self(), {:product_picker_cancelled, "stop-picker"}) end}
      />
    </div>
    """
  end
end
