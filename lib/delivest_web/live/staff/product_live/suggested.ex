defmodule DelivestWeb.Staff.ProductLive.Suggested do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Net}
  alias DelivestWeb.Staff.ProductLive.BranchProducts

  import DelivestWeb.Staff.ProductLive.ProductTags, only: [tabs: 1]

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
       can_edit: Identity.can?(socket.assigns.current_staff, "products.update")
     )
     |> load()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket |> assign(search: params["search"] || "", only: params["only"] == "true") |> filter()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    with {:ok, product} <- Net.get_branch_product(socket.assigns.branch_id, id),
         {:ok, _product} <-
           Net.update_product(socket.assigns.current_staff, product, %{
             "suggested" => not product.suggested
           }) do
      {:noreply, load(socket)}
    else
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _error -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  @impl true
  def handle_info({event, _product}, socket) when is_atom(event), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket),
    do: socket |> assign(products: BranchProducts.load(socket.assigns.branch_id)) |> filter()

  defp filter(socket) do
    %{products: products, search: search, only: only} = socket.assigns
    keep? = fn product -> not only or product.suggested end
    assign(socket, shown: BranchProducts.filter(products, search, keep?))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Recommended")}
        subtitle={gettext("Recommended products are offered in the cart on the site.")}
      />

      <.tabs current={:suggested} />

      <BranchProducts.filter_form
        id="suggested-filter"
        search={@search}
        only={@only}
        only_label={gettext("Only recommended")}
      />

      <BranchProducts.product_list
        id="suggested-list"
        products={@shown}
        empty={gettext("No products")}
      >
        <:action :let={product}>
          <input
            type="checkbox"
            class="toggle toggle-primary toggle-sm"
            checked={product.suggested}
            disabled={not @can_edit}
            phx-click="toggle"
            phx-value-id={product.id}
            aria-label={gettext("Recommend %{name}", name: product.name)}
          />
        </:action>
      </BranchProducts.product_list>
    </div>
    """
  end
end
