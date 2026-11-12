defmodule DelivestWeb.Staff.MenuLive.Popular do
  use DelivestWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Delivest.{Identity, Net, Popular}
  alias DelivestWeb.Staff.ProductLive.BranchProducts

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    if connected?(socket), do: Net.Products.subscribe_branch(branch_id)

    settings = Popular.get_settings(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Popular products"),
       branch_id: branch_id,
       can_edit: Identity.can?(socket.assigns.current_staff, "products.update"),
       search: "",
       picker_open: false,
       mode: settings.mode,
       auto_limit: settings.auto_limit,
       settings_form: to_form(Popular.change_settings(settings, %{}), as: "popular")
     )
     |> load()}
  end

  @impl true
  def handle_event("settings", %{"popular" => params}, socket) do
    settings = Popular.change_settings(settings(socket), params)
    {:noreply, assign(socket, settings_form: to_form(settings, as: "popular"))}
  end

  def handle_event("save_settings", %{"popular" => params}, socket) do
    case Popular.update_settings(socket.assigns.current_staff, socket.assigns.branch_id, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(
           mode: settings.mode,
           picker_open: settings.mode == :manual and socket.assigns.picker_open,
           auto_limit: settings.auto_limit,
           settings_form: to_form(Popular.change_settings(settings, %{}), as: "popular")
         )
         |> load()
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(settings_form: to_form(Map.put(changeset, :action, :validate), as: "popular"))
         |> put_flash(:error, gettext("Please check the highlighted fields"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("recalculate", _params, socket) do
    case Popular.recalculate(socket.assigns.current_staff, socket.assigns.branch_id) do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, gettext("Popular products recalculated"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("filter", params, socket) do
    {:noreply, assign(socket, search: params["search"] || "") |> filter()}
  end

  def handle_event("open_picker", _, socket), do: {:noreply, assign(socket, picker_open: true)}

  def handle_event("toggle", %{"id" => id}, socket) do
    branch_id = socket.assigns.branch_id

    result =
      if id in socket.assigns.picked_ids do
        Popular.remove_product(socket.assigns.current_staff, branch_id, id)
      else
        Popular.add_product(socket.assigns.current_staff, branch_id, id)
      end

    case result do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Popular.remove_product(socket.assigns.current_staff, socket.assigns.branch_id, id) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket) do
    ids = socket.assigns.picked_ids
    index = Enum.find_index(ids, &(&1 == id))
    target = if direction == "up", do: index && index - 1, else: index && index + 1

    if is_integer(target) and target >= 0 and target < length(ids) do
      reordered =
        ids |> List.replace_at(index, Enum.at(ids, target)) |> List.replace_at(target, id)

      case Popular.reorder(socket.assigns.current_staff, socket.assigns.branch_id, reordered) do
        {:ok, _} -> {:noreply, load(socket)}
        _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:product_picker_cancelled, "popular-picker"}, socket),
    do: {:noreply, assign(socket, picker_open: false)}

  def handle_info({:product_picker_confirmed, "popular-picker", ids}, socket) do
    result =
      if Popular.get_settings(socket.assigns.branch_id).mode == :manual do
        Popular.replace_products(socket.assigns.current_staff, socket.assigns.branch_id, ids)
      else
        {:error, :invalid_mode}
      end

    case result do
      {:ok, _} -> {:noreply, socket |> assign(picker_open: false) |> load()}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_info({event, _product}, socket) when is_atom(event), do: {:noreply, load(socket)}
  def handle_info(:catalog_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp settings(socket) do
    settings = Popular.get_settings(socket.assigns.branch_id)

    %{settings | mode: socket.assigns.mode, auto_limit: socket.assigns.auto_limit}
  end

  defp load(socket) do
    branch_id = socket.assigns.branch_id
    picked_ids = Popular.list_product_ids(branch_id)
    picked = Popular.list_products(branch_id)
    products = BranchProducts.load(branch_id)

    socket
    |> assign(picked_ids: picked_ids, picked: picked, products: products)
    |> filter()
  end

  defp filter(socket) do
    %{products: products, search: search} = socket.assigns
    assign(socket, shown: BranchProducts.filter(products, search, fn _ -> true end))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Popular products")}
        subtitle={gettext("The products the app shows in the popular block of the menu.")}
        title_in_header={false}
      >
        <:actions :if={@can_edit}>
          <button
            type="submit"
            form="popular-settings"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >{gettext("Save")}</button>
        </:actions>
      </.page_header>

      <button
        :if={@can_edit and @mode == :auto}
        id="popular-recalculate"
        type="button"
        phx-click="recalculate"
        class="btn btn-outline"
      >{gettext("Recalculate")}</button>

      <.form
        for={@settings_form}
        id="popular-settings"
        phx-change="settings"
        phx-submit="save_settings"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div :if={@can_edit} class="flex flex-wrap gap-2">
          <label
            :for={{value, label} <- mode_options()}
            class="flex cursor-pointer items-center gap-2"
          >
            <input
              type="radio"
              name="popular[mode]"
              value={value}
              checked={to_string(@mode) == value}
              class="radio radio-primary radio-sm"
            />
            <span>{label}</span>
          </label>
        </div>

        <div :if={@mode == :auto} class="max-w-xs space-y-2">
          <.input
            field={@settings_form[:auto_limit]}
            type="number"
            min={1}
            max={24}
            label={gettext("How many products to pick automatically")}
            disabled={not @can_edit}
          />
          <p class="text-sm text-base-content/60">
            {gettext("The app picks the best-selling products of the last 30 days automatically.")}
          </p>
        </div>

        <div class="flex flex-wrap gap-6">
          <.input
            field={@settings_form[:show_in_menu]}
            type="checkbox"
            label={gettext("Show in menu")}
            disabled={not @can_edit}
          />
          <.input
            field={@settings_form[:show_in_cart]}
            type="checkbox"
            label={gettext("Show in cart")}
            disabled={not @can_edit}
          />
        </div>

        <p :if={@mode == :manual} class="text-sm text-base-content/60">
          {gettext("Pick the products by hand below and set their order.")}
        </p>
        <p :if={@mode == :off} class="text-sm text-base-content/60">
          {gettext("The popular block is hidden in the app.")}
        </p>
      </.form>

      <section :if={@mode != :off} class="space-y-3">
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="font-bold">{gettext("Shown in the app")}</h2><button
              :if={@can_edit and @mode == :manual}
              id="popular-add-products"
              type="button"
              class="btn btn-primary"
              phx-click={JS.push_focus() |> JS.push("open_picker")}
            >{gettext("Add products")}</button>
          </div>

          <div
            :if={@mode == :auto}
            id="popular-preview-auto"
            class="rounded-box border border-base-300 bg-base-100"
          >
            <ul class="divide-y divide-base-200">
              <li :if={@picked == []} class="px-4 py-3 text-sm text-base-content/60">
                {gettext("No products yet. Make sure there are sales in the last 30 days.")}
              </li>
              <li
                :for={product <- @picked}
                id={"popular-auto-#{product.id}"}
                class="px-4 py-2 font-bold"
              >
                {product.name}
              </li>
            </ul>
          </div>

          <div
            :if={@mode == :manual}
            id="popular-picked"
            class="rounded-box border border-base-300 bg-base-100"
          >
            <ul class="divide-y divide-base-200">
              <li :if={@picked == []} class="px-4 py-3 text-sm text-base-content/60">
                {gettext("No products picked yet.")}
              </li>
              <li
                :for={product <- @picked}
                id={"popular-picked-#{product.id}"}
                class="flex items-center justify-between gap-2 px-4 py-2"
              >
                <span class="font-bold">{product.name}</span>
                <span :if={@can_edit} class="flex items-center gap-1">
                  <button
                    type="button"
                    phx-click="move"
                    phx-value-id={product.id}
                    phx-value-direction="up"
                    class="btn btn-ghost btn-xs"
                    aria-label={gettext("Move up")}
                  >↑</button>
                  <button
                    type="button"
                    phx-click="move"
                    phx-value-id={product.id}
                    phx-value-direction="down"
                    class="btn btn-ghost btn-xs"
                    aria-label={gettext("Move down")}
                  >↓</button>
                  <button
                    type="button"
                    phx-click="remove"
                    phx-value-id={product.id}
                    class="btn btn-ghost btn-xs text-error"
                    aria-label={gettext("Remove")}
                  >✕</button>
                </span>
              </li>
            </ul>
          </div>
        </div>
      </section>
      <.live_component
        :if={@picker_open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="popular-picker"
        products={@products}
        selected_ids={@picked_ids}
        title={gettext("Add products")}
        on_save={fn ids -> send(self(), {:product_picker_confirmed, "popular-picker", ids}) end}
        on_cancel={fn -> send(self(), {:product_picker_cancelled, "popular-picker"}) end}
      />
    </div>
    """
  end

  defp mode_options do
    [
      {"off", gettext("Off")},
      {"auto", gettext("Automatically pick popular products")},
      {"manual", gettext("Pick products manually")}
    ]
  end
end
