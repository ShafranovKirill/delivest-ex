defmodule DelivestWeb.Staff.DeliveryLive.Address do
  use DelivestWeb, :live_view

  alias Delivest.{Delivery, Identity}
  alias Delivest.Integrations.Dadata

  on_mount {DelivestWeb.Hooks.Permission, "delivery.read"}

  @impl true
  def mount(_params, _session, socket) do
    settings = Delivery.get_settings(socket.assigns.current_branch.id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Customer address selection"),
       can_edit: Identity.can?(socket.assigns.current_staff, "delivery.update"),
       dadata_active: Dadata.active?()
     )
     |> assign_settings(settings)}
  end

  @impl true
  def handle_event("change", %{"address" => params}, socket) do
    params = Map.merge(socket.assigns.form.params, params)

    {:noreply,
     assign(socket,
       form: to_form(params, as: "address"),
       map_mode: params["map_address"] == "true"
     )}
  end

  def handle_event("save", %{"address" => params}, socket) do
    map_mode = params["map_address"] == "true"

    if map_mode and not Dadata.active?() do
      {:noreply,
       put_flash(socket, :error, gettext("Configure DaData before enabling map selection."))}
    else
      attrs =
        params
        |> Map.take(["map_address", "show_city", "operator_address"])
        |> Map.put("address_mode_set", true)

      case Delivery.update_settings(
             socket.assigns.current_staff,
             socket.assigns.current_branch.id,
             attrs
           ) do
        {:ok, settings} ->
          {:noreply,
           socket |> assign_settings(settings) |> put_flash(:info, gettext("Settings saved"))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: "address"))}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      end
    end
  end

  defp assign_settings(socket, settings) do
    params = %{
      "map_address" => to_string(settings.map_address != false),
      "show_city" => settings.show_city == true,
      "operator_address" => settings.operator_address == true
    }

    assign(socket,
      form: to_form(params, as: "address"),
      map_mode: settings.map_address != false,
      zone_mode: settings.mode == :zones
    )
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Customer address selection")}
      back={~p"/staff/b/#{@current_branch}/delivery"}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-[calc(100dvh-var(--staff-header-height)-2rem)] flex-col justify-center sm:min-h-[calc(100dvh-var(--staff-header-height)-3rem)]">
      <.form
        for={@form}
        id="address-settings"
        phx-change="change"
        phx-submit="save"
        class="mx-auto w-full max-w-xl space-y-5 rounded-box border border-base-300 bg-base-100 p-4 shadow-sm sm:space-y-6 sm:p-8"
      >
        <fieldset class="grid gap-2 sm:grid-cols-2 sm:gap-3">
          <legend class="mb-4 w-full text-center text-lg font-semibold sm:text-xl">
            {gettext("How customers choose a delivery address")}
          </legend>
          <label class="flex min-h-14 cursor-pointer items-center gap-3 rounded-box border border-base-300 px-4 py-3 text-sm font-medium has-checked:border-primary has-checked:bg-primary/5">
            <input
              type="radio"
              class="radio radio-primary radio-sm shrink-0"
              name="address[map_address]"
              value="true"
              checked={@map_mode}
              disabled={not @can_edit}
            />
            {gettext("On the map")}
          </label>
          <label class="flex min-h-14 cursor-pointer items-center gap-3 rounded-box border border-base-300 px-4 py-3 text-sm font-medium has-checked:border-primary has-checked:bg-primary/5">
            <input
              type="radio"
              class="radio radio-primary radio-sm shrink-0"
              name="address[map_address]"
              value="false"
              checked={not @map_mode}
              disabled={not @can_edit}
            />
            {gettext("Manually in the order form")}
          </label>
        </fieldset>

        <div :if={@map_mode} class="space-y-2 rounded-box bg-base-200/60 p-4 text-sm">
          <p>{gettext("Customers confirm their address on the map before checkout.")}</p>
          <p :if={not @dadata_active} class="text-warning">
            {gettext("Configure DaData before enabling map selection.")}
          </p>
          <.link
            navigate={~p"/staff/b/#{@current_branch}/integrations/dadata"}
            class="link link-primary"
          >
            {gettext("DaData integration settings")}
          </.link>
        </div>

        <div
          :if={not @map_mode}
          class="space-y-3 rounded-box bg-base-200/60 p-4 [&_.checkbox]:shrink-0 [&_.label-text]:whitespace-normal"
        >
          <.input
            field={@form[:show_city]}
            type="checkbox"
            label={gettext("Show city in the order form")}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:operator_address]}
            type="checkbox"
            label={gettext("Allow customers to tell the address to an operator")}
            disabled={not @can_edit}
          />
          <p class="text-sm text-base-content/70">
            <span :if={@zone_mode}>
              {gettext(
                "Manual addresses use the branch's flat delivery price. Your delivery zones stay saved for map mode."
              )}
            </span>
            <.link navigate={~p"/staff/b/#{@current_branch}/delivery/zones"} class="link link-primary">
              {gettext("Edit delivery prices")}
            </.link>
          </p>
        </div>

        <div :if={@can_edit} class="flex justify-end border-t border-base-300 pt-4">
          <button type="submit" class="btn btn-primary min-h-12 w-full sm:w-auto sm:min-w-32">
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
