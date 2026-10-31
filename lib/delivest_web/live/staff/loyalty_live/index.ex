defmodule DelivestWeb.Staff.LoyaltyLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Loyalty}
  alias Delivest.Identity.Branch.LoyaltySettings

  on_mount {DelivestWeb.Hooks.GatewayArea, :loyalty}
  on_mount {DelivestWeb.Hooks.Permission, "promotions.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch = socket.assigns.current_branch

    {:ok,
     socket
     |> assign(
       page_title: gettext("Loyalty"),
       can_edit: Identity.can?(socket.assigns.current_staff, "promotions.update"),
       summary: Loyalty.summary(branch.id),
       product_search: "",
       configured_only: false,
       configured_count: Enum.count(Delivest.Net.list_branch_products(branch.id), &configured?/1)
     )
     |> stream(:products, Delivest.Net.list_branch_products(branch.id))
     |> assign_form(LoyaltySettings.changeset(Loyalty.settings(branch), %{}))}
  end

  @impl true
  def handle_event("validate", %{"loyalty" => params}, socket) do
    changeset =
      socket.assigns.current_branch
      |> Loyalty.settings()
      |> LoyaltySettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("filter_products", params, socket) do
    socket =
      assign(socket,
        product_search: params["search"] || "",
        configured_only: params["configured"] == "true"
      )

    products = Delivest.Net.list_branch_products(socket.assigns.current_branch.id)
    query = String.downcase(String.trim(socket.assigns.product_search))

    products =
      Enum.filter(products, fn product ->
        (not socket.assigns.configured_only or configured?(product)) and
          String.contains?(String.downcase(product.name), query)
      end)

    {:noreply, stream(socket, :products, products, reset: true)}
  end

  def handle_event("product", %{"product_id" => id} = params, socket) do
    case Loyalty.set_product(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           id,
           params
         ) do
      {:ok, product} ->
        count =
          socket.assigns.current_branch.id
          |> Delivest.Net.list_branch_products()
          |> Enum.count(&configured?/1)

        socket = assign(socket, configured_count: count)

        socket =
          if socket.assigns.configured_only and not configured?(product),
            do: stream_delete(socket, :products, product),
            else: stream_insert(socket, :products, product)

        {:noreply, socket |> put_flash(:info, gettext("Settings saved"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("save", %{"loyalty" => params}, socket) do
    case Identity.update_loyalty(
           socket.assigns.current_staff,
           socket.assigns.current_branch,
           params
         ) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(current_branch: branch)
         |> assign_form(LoyaltySettings.changeset(Loyalty.settings(branch), %{}))
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, :info, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :validate))
         |> put_flash(:error, gettext("Failed to save"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp configured?(product),
    do: not is_nil(product.stars_price) or not is_nil(product.stars_reward)

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "loyalty"))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-5xl">
      <.page_header
        title={gettext("Loyalty")}
        subtitle={gettext("Customers earn stars for completed orders.")}
      />

      <div id="loyalty-summary" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div
          :for={
            {key, label} <- [
              {:issued, gettext("Stars issued")},
              {:reversed, gettext("Stars returned")},
              {:expired, gettext("Expired")},
              {:liability, gettext("Balance owed")}
            ]
          }
          id={"loyalty-summary-#{key}"}
          class="rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="text-sm text-base-content/60">{label}</div>
          <div class="mt-1 flex items-center gap-1 text-2xl font-bold text-amber-500">
            <.icon name="hero-star-solid" class="size-5" />
            {Map.fetch!(@summary, key)}
          </div>
        </div>
      </div>

      <.form
        for={@form}
        id="loyalty-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("Loyalty program in this branch")}
          disabled={not @can_edit}
        />
        <div class="grid sm:grid-cols-2 gap-4">
          <.input
            field={@form[:per_rubles]}
            type="number"
            min="1"
            label={gettext("For every, ₽")}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:stars]}
            type="number"
            min="1"
            label={gettext("Stars")}
            disabled={not @can_edit}
          />
        </div>
        <.input
          field={@form[:expire_days]}
          type="number"
          min="1"
          label={gettext("Stars expire after, days")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:shop_enabled]}
          type="checkbox"
          label={gettext("Products for stars")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:spend_enabled]}
          type="checkbox"
          label={gettext("Customers can pay part of an order with stars")}
          disabled={not @can_edit}
        />
        <.input
          :if={@form[:spend_enabled].value in [true, "true"]}
          field={@form[:max_percent]}
          type="number"
          min="1"
          max="100"
          label={gettext("At most, % of the order total")}
          disabled={not @can_edit}
        />
        <p class="text-sm text-base-content/60">
          {gettext(
            "Stars are counted from the order total after discounts, without delivery, and rounded down. They are credited when the order is completed."
          )}
        </p>
        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
      <details
        id="loyalty-product-settings"
        class="group rounded-box border border-base-300 bg-base-100"
      >
        <summary class="flex cursor-pointer list-none items-center justify-between gap-3 p-5">
          <span>
            <span class="block font-bold text-lg">{gettext("Product bonus settings")}</span>
            <span id="loyalty-configured-count" class="text-sm text-base-content/60">
              {gettext("Configured: %{count}", count: @configured_count)}
            </span>
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-5 shrink-0 transition-transform group-open:rotate-180"
          />
        </summary>
        <div class="border-t border-base-300">
          <form
            id="loyalty-product-filter"
            phx-change="filter_products"
            class="flex flex-wrap items-center gap-4 p-4"
          >
            <input
              type="search"
              name="search"
              value={@product_search}
              placeholder={gettext("Search products by name...")}
              phx-debounce="200"
              aria-label={gettext("Search products by name...")}
              class="input min-w-48 flex-1"
            />
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="configured"
                value="true"
                checked={@configured_only}
                class="checkbox checkbox-sm"
              />
              {gettext("Configured only")}
            </label>
          </form>
          <p class="px-4 pb-4 text-sm text-base-content/60">
            {gettext(
              "Empty price: not sold for stars. Empty reward: general rate. Zero reward: no stars earned."
            )}
          </p>
          <div class="overflow-x-auto">
            <table class="table w-full">
              <thead class="bg-base-200/50">
                <tr>
                  <th>{gettext("Product")}</th>
                  <th class="w-36">{gettext("Price in stars")}</th>
                  <th class="w-36">{gettext("Stars per product")}</th>
                  <th class="w-28"><span class="sr-only">{gettext("Save")}</span></th>
                </tr>
              </thead>
              <tbody id="loyalty-products" phx-update="stream">
                <tr id="loyalty-products-empty" class="hidden only:table-row">
                  <td colspan="4" class="py-8 text-center text-base-content/50">
                    {gettext("No products found")}
                  </td>
                </tr>
                <tr
                  :for={{dom_id, product} <- @streams.products}
                  id={dom_id}
                  class="hover:bg-base-200/30"
                >
                  <td>
                    <span class="font-medium">{product.name}</span>
                    <span
                      :if={configured?(product)}
                      class="ml-2 inline-block size-2 rounded-full bg-amber-500"
                      title={gettext("Configured")}
                    />
                  </td>
                  <td>
                    <input
                      type="number"
                      form={"bonus-form-#{product.id}"}
                      name="stars_price"
                      value={product.stars_price}
                      min="1"
                      placeholder="—"
                      aria-label={gettext("Price in stars")}
                      class="input input-sm w-28 font-mono"
                      disabled={not @can_edit}
                    />
                  </td>
                  <td>
                    <input
                      type="number"
                      form={"bonus-form-#{product.id}"}
                      name="stars_reward"
                      value={product.stars_reward}
                      min="0"
                      placeholder="—"
                      aria-label={gettext("Stars per product")}
                      class="input input-sm w-28 font-mono"
                      disabled={not @can_edit}
                    />
                  </td>
                  <td>
                    <form id={"bonus-form-#{product.id}"} phx-submit="product">
                      <input type="hidden" name="product_id" value={product.id} />
                      <button
                        :if={@can_edit}
                        class="btn btn-sm btn-ghost"
                        phx-disable-with={gettext("Saving...")}
                      >{gettext("Save")}</button>
                    </form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </details>
    </div>
    """
  end
end
