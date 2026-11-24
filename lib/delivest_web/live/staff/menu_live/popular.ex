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
       calculated_at: settings.calculated_at,
       settings_form: to_form(Popular.change_settings(settings, %{}), as: "popular")
     )
     |> load()}
  end

  @impl true
  def handle_event("settings", %{"popular" => params}, socket) do
    settings = Popular.change_settings(Popular.get_settings(socket.assigns.branch_id), params)
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
           calculated_at: settings.calculated_at,
           settings_form: to_form(Popular.change_settings(settings, %{}), as: "popular")
         )
         |> load()
         |> put_flash(:info, gettext("Settings saved"))
         |> push_event("staff:form-saved", %{})}

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

  def handle_event("open_picker", _, socket) do
    if socket.assigns.can_edit and socket.assigns.mode == :manual,
      do: {:noreply, assign(socket, picker_open: true)},
      else: {:noreply, socket}
  end

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

  defp load(socket) do
    branch_id = socket.assigns.branch_id
    picked_ids = Popular.list_product_ids(branch_id)
    picked = Popular.list_products(branch_id)
    products = BranchProducts.load(branch_id)

    socket
    |> assign(
      picked_ids: picked_ids,
      picked: picked,
      products: products,
      calculated_at: Popular.get_settings(branch_id).calculated_at
    )
    |> filter()
  end

  defp draft_mode(form), do: Ecto.Changeset.get_field(form.source, :mode)
  defp settings_dirty?(form), do: form.source.changes != %{}

  defp filter(socket) do
    %{products: products, search: search} = socket.assigns
    assign(socket, shown: BranchProducts.filter(products, search, fn _ -> true end))
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_toolbar
      id="popular-toolbar"
      title={gettext("Popular products")}
      back={~p"/staff/b/#{@current_branch}/products/collections"}
    >
      <:primary_action :if={@can_edit}>
        <button
          type="submit"
          form="popular-settings"
          class={if(@mode == :manual, do: "btn btn-outline btn-sm", else: "btn btn-primary btn-sm")}
          phx-disable-with={gettext("Saving...")}
        >{gettext("Save")}</button>
        <button
          :if={@mode == :manual}
          id="popular-add-products"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click={JS.push_focus() |> JS.push("open_picker")}
        >{gettext("Add products")}</button>
      </:primary_action>
      <:more_actions :if={@can_edit and @mode == :auto}>
        <button
          :if={@mode == :auto}
          id="popular-recalculate"
          type="button"
          phx-click="recalculate"
          class="btn btn-ghost btn-sm justify-start"
        >{gettext("Recalculate")}</button>
      </:more_actions>
    </.page_toolbar>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        draft_mode: draft_mode(assigns.settings_form),
        settings_dirty: settings_dirty?(assigns.settings_form)
      )

    ~H"""
    <div class="space-y-5">
      <.form
        for={@settings_form}
        id="popular-settings"
        phx-change="settings"
        data-staff-dirty
        phx-submit="save_settings"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-4 sm:p-5"
      >
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold">{gettext("Collection settings")}</h2>
          <span
            :if={@settings_dirty}
            id="popular-settings-dirty"
            class="badge badge-warning badge-outline"
          >{gettext("Unsaved settings")}</span>
        </div>

        <div class="grid gap-4 md:grid-cols-2 md:gap-6">
          <div class="space-y-2">
            <.input
              field={@settings_form[:mode]}
              type="select"
              options={mode_options()}
              label={gettext("How to choose products")}
              disabled={not @can_edit}
              class="select select-bordered select-sm w-full"
            />
            <div :if={@draft_mode == :auto} class="flex items-end gap-3">
              <div class="w-36 shrink-0">
                <.input
                  field={@settings_form[:auto_limit]}
                  type="number"
                  min={1}
                  max={24}
                  label={gettext("Product limit")}
                  disabled={not @can_edit}
                />
              </div>
              <p class="pb-2 text-xs text-base-content/60">
                {gettext("The app picks the best-selling products of the last 30 days automatically.")}
              </p>
            </div>
          </div>
          <div class="md:border-l md:border-base-200 md:pl-6">
            <h3 class="mb-2 text-sm font-semibold">{gettext("Where to show")}</h3>
            <div class="grid gap-2">
              <div>
                <.input
                  field={@settings_form[:show_in_menu]}
                  type="checkbox"
                  label={gettext("Show in menu")}
                  disabled={not @can_edit}
                />
                <p class="pl-7 text-xs text-base-content/60">
                  {gettext("In a separate category in the menu.")}
                </p>
              </div>
              <div>
                <.input
                  field={@settings_form[:show_in_cart]}
                  type="checkbox"
                  label={gettext("Show in cart")}
                  disabled={not @can_edit}
                />
                <p class="pl-7 text-xs text-base-content/60">
                  {gettext("As additional offers in the cart.")}
                </p>
              </div>
            </div>
          </div>
        </div>
      </.form>

      <section id="popular-products-section" class="space-y-3">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="font-semibold">{gettext("Products in collection")}</h2>
          <span :if={@mode != :off} class="text-sm text-base-content/60">{gettext("%{count} products",
            count: length(@picked)
          )}</span>
        </div>
        <p :if={@draft_mode != @mode and @mode != :off} class="text-sm text-base-content/60">
          {gettext("Save settings to apply the selected mode.")}
        </p>
        <div
          :if={@mode == :off}
          id="popular-off-empty"
          class="rounded-box border border-dashed border-base-300 bg-base-100 px-4 py-5 text-sm text-base-content/70"
        >
          <%= if @draft_mode == :off do %>
            {gettext("Choose how to build the collection, then save settings.")}
          <% else %>
            {gettext("Save settings to apply the selected mode.")}
          <% end %>
        </div>

        <div :if={@mode != :off} class="space-y-3">
          <p :if={@mode == :auto} class="text-sm text-base-content/60">
            {gettext("Based on sales over the last 30 days.")}
            <span :if={@calculated_at}>{gettext("Last calculated: %{date}",
              date:
                @calculated_at
                |> Delivest.LocalTime.local(@current_branch)
                |> Calendar.strftime("%d.%m.%Y %H:%M %Z")
            )}</span>
          </p>
          <p :if={@mode == :manual} class="text-sm text-base-content/60">
            {gettext("Set the order with the arrow buttons.")}
          </p>

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
      {gettext("Off"), "off"},
      {gettext("By sales"), "auto"},
      {gettext("Manually"), "manual"}
    ]
  end
end
