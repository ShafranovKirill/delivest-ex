defmodule DelivestWeb.Staff.ProductLive.StopList do
  use DelivestWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Delivest.{Identity, Net}
  alias Delivest.Net.Stops
  alias DelivestWeb.Staff.ProductLive.BranchProducts

  import DelivestWeb.Staff.ProductLive.StopControl, only: [stop_control: 1]

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
       search: "",
       only: false,
       picker_open: false,
       can_edit: Identity.can?(socket.assigns.current_staff, "stops.update")
     )
     |> load()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket |> assign(search: params["search"] || "", only: params["only"] == "true") |> filter()}
  end

  def handle_event("open_picker", _, socket), do: {:noreply, assign(socket, picker_open: true)}

  def handle_event("stop", %{"id" => id, "period" => period}, socket)
      when period in ~w(today until_resumed) do
    with_product(socket, id, fn product ->
      Stops.stop(
        socket.assigns.current_staff,
        socket.assigns.branch_id,
        product,
        String.to_existing_atom(period)
      )
    end)
  end

  def handle_event("resume", %{"id" => id}, socket) do
    with_product(socket, id, fn product ->
      Stops.resume(socket.assigns.current_staff, socket.assigns.branch_id, product)
    end)
  end

  @impl true
  def handle_info({:product_picker_cancelled, "stop-picker"}, socket),
    do: {:noreply, assign(socket, picker_open: false)}

  def handle_info({:product_picker_confirmed, "stop-picker", ids}, socket) do
    branch_id = socket.assigns.branch_id
    staff = socket.assigns.current_staff
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
      {:ok, _} -> {:noreply, socket |> assign(picker_open: false) |> load()}
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
    socket
    |> assign(
      products: BranchProducts.load(socket.assigns.branch_id),
      stops: Stops.by_product(socket.assigns.branch_id)
    )
    |> filter()
  end

  defp filter(socket) do
    %{products: products, stops: stops, search: search, only: only} = socket.assigns
    keep? = fn product -> not only or Map.has_key?(stops, product.id) end
    assign(socket, shown: BranchProducts.filter(products, search, keep?))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title={gettext("Stop list")}
        layout={:two_rows}
        title_in_header={false}
      >
      </.page_header>

      <button
        :if={@can_edit}
        id="stop-add-products"
        type="button"
        class="btn btn-primary"
        phx-click={JS.push_focus() |> JS.push("open_picker")}
      >{gettext("Add products")}</button>

      <BranchProducts.product_list
        id="stop-list"
        products={Enum.filter(@products, &Map.has_key?(@stops, &1.id))}
        empty={gettext("No products")}
      >
        <:action :let={product}>
          <.stop_control
            product={product}
            stops={Map.get(@stops, product.id, [])}
            can_edit={@can_edit}
          />
        </:action>
      </BranchProducts.product_list>
      <.live_component
        :if={@picker_open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="stop-picker"
        products={@products}
        selected_ids={Map.keys(@stops)}
        title={gettext("Add products")}
        on_save={fn ids -> send(self(), {:product_picker_confirmed, "stop-picker", ids}) end}
        on_cancel={fn -> send(self(), {:product_picker_cancelled, "stop-picker"}) end}
      />
    </div>
    """
  end
end
