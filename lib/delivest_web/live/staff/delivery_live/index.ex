defmodule DelivestWeb.Staff.DeliveryLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Delivery, Identity}
  alias Delivest.Delivery.Conditions
  alias DelivestWeb.Staff.DeliveryLive.ZonePanel

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    settings = Delivery.get_settings(branch_id)
    zones = Delivery.list_zones(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Delivery"),
       can_edit: Identity.can?(socket.assigns.current_staff, "branches.update"),
       mode: settings.mode,
       branch_point: branch_point(branch_id),
       address_map: Delivest.Integrations.Dadata.active?()
     )
     |> assign_settings(settings)
     |> assign_zones(zones, zones |> List.first() |> then(&(&1 && &1.id)))}
  end

  @impl true
  def handle_event("mode", %{"delivery" => %{"mode" => mode}}, socket),
    do: {:noreply, assign(socket, mode: String.to_existing_atom(mode))}

  def handle_event("save_settings", %{"delivery" => params}, socket) do
    attrs = %{"mode" => params["mode"], "thresholds" => Conditions.to_thresholds(params)}

    case Delivery.update_settings(socket.assigns.current_staff, branch_id(socket), attrs) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(mode: settings.mode)
         |> assign_settings(settings)
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("draw_zone", _params, socket),
    do: {:noreply, push_event(socket, "zones:draw", %{})}

  def handle_event("zone_drawn", %{"polygon" => polygon}, socket) do
    case Delivery.create_zone(socket.assigns.current_staff, branch_id(socket), polygon) do
      {:ok, zone} ->
        {:noreply, socket |> reload_zones(zone.id) |> push_zones()}

      {:error, reason} ->
        {:noreply, socket |> push_zones() |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("zone_shape", %{"id" => id, "polygon" => polygon}, socket) do
    case Delivery.update_zone_polygon(
           socket.assigns.current_staff,
           branch_id(socket),
           id,
           polygon
         ) do
      {:ok, _zone} ->
        {:noreply, reload_zones(socket, id)}

      {:error, reason} ->
        {:noreply, socket |> push_zones() |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("zone_selected", %{"id" => id}, socket),
    do: {:noreply, select(socket, id)}

  def handle_event("select_zone", %{"id" => id}, socket),
    do: {:noreply, socket |> select(id) |> push_zones()}

  def handle_event("save_zone", %{"zone" => params}, socket) do
    attrs =
      params
      |> Map.take(["name", "color", "enabled", "delivery_minutes"])
      |> Map.put("thresholds", Conditions.to_thresholds(params))

    staff = socket.assigns.current_staff

    case Delivery.update_zone(staff, branch_id(socket), socket.assigns.selected_id, attrs) do
      {:ok, zone} ->
        {:noreply,
         socket
         |> reload_zones(zone.id)
         |> push_zones()
         |> put_flash(:info, gettext("Zone saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, zone_form: to_form(changeset, as: "zone"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("delete_zone", %{"id" => id}, socket) do
    case Delivery.delete_zone(socket.assigns.current_staff, branch_id(socket), id) do
      {:ok, _zone} -> {:noreply, socket |> reload_zones(nil) |> push_zones()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  defp branch_id(socket), do: socket.assigns.current_branch.id

  defp branch_point(branch_id) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, %{info: %{latitude: lat, longitude: lng}}} -> %{lat: lat, lng: lng}
      _ -> %{lat: nil, lng: nil}
    end
  end

  defp assign_settings(socket, settings) do
    params = Map.put(Conditions.from_thresholds(settings.thresholds), "mode", settings.mode)
    assign(socket, settings: settings, settings_form: to_form(params, as: "delivery"))
  end

  defp reload_zones(socket, selected_id) do
    zones = Delivery.list_zones(branch_id(socket))

    selected_id =
      if Enum.any?(zones, &(&1.id == selected_id)), do: selected_id, else: first_id(zones)

    assign_zones(socket, zones, selected_id)
  end

  defp first_id([zone | _]), do: zone.id
  defp first_id([]), do: nil

  defp assign_zones(socket, zones, selected_id) do
    socket
    |> assign(zones: zones)
    |> select(selected_id)
  end

  defp select(socket, id) do
    zone = Enum.find(socket.assigns.zones, &(&1.id == id))
    assign(socket, selected_id: zone && zone.id, zone_form: zone && zone_form(zone))
  end

  defp zone_form(zone) do
    zone
    |> Map.take([:name, :color, :enabled, :delivery_minutes])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.merge(Conditions.from_thresholds(zone.thresholds))
    |> to_form(as: "zone")
  end

  defp push_zones(socket),
    do:
      push_event(socket, "zones:reset", %{
        zones: Enum.map(socket.assigns.zones, &zone_json/1),
        selected: socket.assigns.selected_id
      })

  defp zone_json(zone),
    do: %{id: zone.id, color: zone.color, enabled: zone.enabled, polygon: zone.polygon}

  defp error_message(:forbidden), do: gettext("Permission denied")
  defp error_message(%Ecto.Changeset{} = changeset), do: changeset_message(changeset)
  defp error_message(_reason), do: gettext("Failed to save")

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field}: #{inspect(messages)}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-6xl">
      <.page_header
        title={gettext("Delivery")}
        subtitle={
          gettext(
            "Delivery price for the site and Yandex Eda. Addresses outside the zones are not accepted."
          )
        }
      />

      <.form
        for={@settings_form}
        id="delivery-settings"
        phx-change="mode"
        phx-submit="save_settings"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div class="flex flex-wrap gap-2">
          <label
            :for={{value, label} <- mode_options()}
            class="flex cursor-pointer items-center gap-2"
          >
            <input
              type="radio"
              name="delivery[mode]"
              value={value}
              checked={to_string(@mode) == value}
              class="radio radio-primary radio-sm"
              disabled={not @can_edit}
            />
            <span>{label}</span>
          </label>
        </div>

        <div :if={@mode == :flat} class="space-y-2">
          <p class="text-sm text-base-content/60">
            {gettext(
              "One price for any address. Leave the price empty for free delivery, set «free from» for free delivery from a sum."
            )}
          </p>
          <.conditions form={@settings_form} disabled={not @can_edit} />
        </div>

        <p :if={@mode == :zones} class="text-sm text-base-content/60">
          {gettext("The price depends on the zone of the address. Draw the zones on the map below.")}
        </p>

        <div
          :if={@mode == :zones and not @address_map}
          role="alert"
          class="alert alert-warning text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <span>
            {gettext(
              "Zones need DaData: without it the site has no address map, addresses have no point and delivery orders are refused."
            )}
          </span>
        </div>

        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <section
        :if={@mode == :zones}
        id="delivery-zones"
        class="grid gap-4 lg:grid-cols-[1fr_22rem]"
      >
        <div class="space-y-2">
          <div
            id="delivery-zone-map"
            phx-hook="ZoneMap"
            phx-update="ignore"
            data-lat={@branch_point.lat}
            data-lng={@branch_point.lng}
            data-editable={to_string(@can_edit)}
            data-selected={@selected_id}
            data-zones={Jason.encode!(Enum.map(@zones, &zone_json/1))}
            class="h-[32rem] overflow-hidden rounded-box border border-base-300"
          />
          <p :if={@can_edit} class="text-xs text-base-content/60">
            {gettext(
              "Click a zone to edit its points: drag a point, drag a midpoint to add one, right click a point to delete it."
            )}
          </p>
        </div>

        <ZonePanel.panel
          zones={@zones}
          selected_id={@selected_id}
          form={@zone_form}
          can_edit={@can_edit}
        />
      </section>
    </div>
    """
  end

  defp mode_options,
    do: [{"flat", gettext("Without zones")}, {"zones", gettext("By zones on the map")}]

  attr :form, Phoenix.HTML.Form, required: true
  attr :disabled, :boolean, default: false

  def conditions(assigns) do
    ~H"""
    <div class="grid gap-3 sm:grid-cols-3">
      <.input
        field={@form[:min_order]}
        type="number"
        min="0"
        label={gettext("Minimum order, ₽")}
        placeholder="0"
        disabled={@disabled}
      />
      <.input
        field={@form[:price]}
        type="number"
        min="0"
        label={gettext("Delivery price, ₽")}
        placeholder="0"
        disabled={@disabled}
      />
      <.input
        field={@form[:free_from]}
        type="number"
        min="0"
        label={gettext("Free from, ₽")}
        disabled={@disabled}
      />
    </div>
    """
  end
end
