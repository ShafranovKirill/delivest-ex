defmodule DelivestWeb.Staff.ProductLive.Suggested do
  use DelivestWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Delivest.{Identity, Net}
  alias DelivestWeb.Staff.ProductLive.BranchProducts

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    if connected?(socket), do: Net.Products.subscribe_branch(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Recommended"),
       branch_id: branch_id,
       search: "",
       only: false,
       picker_open: false,
       can_edit: Identity.can?(socket.assigns.current_staff, "products.update")
     )
     |> load()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket |> assign(search: params["search"] || "", only: params["only"] == "true") |> filter()}
  end

  def handle_event("open_picker", _, socket), do: {:noreply, assign(socket, picker_open: true)}

  def handle_event("toggle", %{"id" => id}, socket) do
    with {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id),
         {:ok, _product} <-
           Net.update_product(Identity.fresh_staff(socket.assigns.current_staff), product, %{
             "suggested" => not product.suggested
           }) do
      {:noreply, load(socket)}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _error -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id),
         {:ok, _} <-
           Net.update_product(Identity.fresh_staff(socket.assigns.current_staff), product, %{
             "suggested" => false
           }) do
      {:noreply, load(socket)}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  @impl true
  def handle_info({:product_picker_cancelled, "suggested-picker"}, socket),
    do: {:noreply, assign(socket, picker_open: false)}

  def handle_info({:product_picker_confirmed, "suggested-picker", ids}, socket) do
    branch_id = socket.assigns.branch_id
    staff = Identity.fresh_staff(socket.assigns.current_staff)
    products = BranchProducts.load(branch_id)
    valid = MapSet.new(Enum.map(products, & &1.id))

    result =
      with :ok <- Identity.authorize(staff, "products.update", branch_id),
           true <- MapSet.subset?(MapSet.new(ids), valid) do
        Delivest.Repo.transaction(fn ->
          Enum.each(products, fn product ->
            desired = product.id in ids

            if product.suggested != desired do
              case Net.update_product(staff, product, %{"suggested" => desired}) do
                {:ok, _} -> :ok
                error -> Delivest.Repo.rollback(error)
              end
            end
          end)
        end)
      else
        false -> {:error, :invalid_products}
        error -> error
      end

    case result do
      {:ok, _} -> {:noreply, socket |> assign(picker_open: false) |> load()}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_info({event, _product}, socket) when is_atom(event), do: {:noreply, load(socket)}
  def handle_info(:catalog_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket),
    do: socket |> assign(products: BranchProducts.load(socket.assigns.branch_id)) |> filter()

  defp filter(socket) do
    %{products: products, search: search, only: only} = socket.assigns
    keep? = fn product -> not only or product.suggested end
    assign(socket, shown: BranchProducts.filter(products, search, keep?))
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Recommended")}
      title_in_header={false}
    >
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <button
        :if={@can_edit}
        id="suggested-add-products"
        type="button"
        class="btn btn-primary"
        phx-click={JS.push_focus() |> JS.push("open_picker")}
      >{gettext("Add products")}</button>

      <BranchProducts.product_list
        id="suggested-list"
        products={Enum.filter(@products, & &1.suggested)}
        empty={gettext("No products")}
      >
        <:action :let={product}>
          <button
            :if={@can_edit}
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="remove"
            phx-value-id={product.id}
            aria-label={gettext("Remove")}
          >{gettext("Remove")}</button>
        </:action>
      </BranchProducts.product_list>
      <.live_component
        :if={@picker_open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="suggested-picker"
        products={@products}
        selected_ids={for p <- @products, p.suggested, do: p.id}
        title={gettext("Add products")}
        on_save={fn ids -> send(self(), {:product_picker_confirmed, "suggested-picker", ids}) end}
        on_cancel={fn -> send(self(), {:product_picker_cancelled, "suggested-picker"}) end}
      />
    </div>
    """
  end
end
