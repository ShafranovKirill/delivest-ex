defmodule DelivestWeb.Staff.DeliveryLive.Zones do
  use DelivestWeb, :live_view

  alias Delivest.{Delivery, Identity, Money}
  alias Delivest.Delivery.Conditions
  alias DelivestWeb.Staff.DeliveryLive.ZonePanel

  on_mount {DelivestWeb.Hooks.Permission, "delivery.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id
    settings = Delivery.get_settings(branch_id)
    zones = Delivery.list_zones(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Delivery zones"),
       can_edit: Identity.can?(socket.assigns.current_staff, "delivery.update"),
       branch_point: branch_point(branch_id),
       address_map: Delivest.Integrations.Dadata.active?()
     )
     |> assign_settings(settings)
     |> assign_zones(zones, zones |> List.first() |> then(&(&1 && &1.id)))}
  end

  @impl true
  def handle_event("mode", %{"delivery" => params}, socket),
    do: {:noreply, assign_settings_form(socket, params)}

  def handle_event("save_settings", %{"delivery" => params}, socket) do
    attrs = Map.take(params, ["mode", "show_zones", "outside_zones"])

    attrs =
      if Map.has_key?(params, "price"),
        do: Map.put(attrs, "thresholds", Conditions.to_thresholds(params)),
        else: attrs

    case Delivery.update_settings(socket.assigns.current_staff, branch_id(socket), attrs) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings(settings)
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("add_radius_zone", %{"radius" => radius}, socket) do
    case Delivery.create_radius_zone(socket.assigns.current_staff, branch_id(socket), radius) do
      {:ok, zone} ->
        {:noreply, socket |> reload_zones(zone.id) |> push_zones()}

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
      |> Map.take(["name", "color", "enabled", "delivery_minutes", "radius_km"])
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
    case Delivery.branch_point(branch_id) do
      {lat, lng} -> %{lat: lat, lng: lng}
      nil -> %{lat: nil, lng: nil}
    end
  end

  defp assign_settings(socket, settings) do
    params =
      settings.thresholds
      |> Conditions.from_thresholds()
      |> Map.merge(%{
        "mode" => to_string(settings.mode),
        "show_zones" => settings.show_zones,
        "outside_zones" => settings.outside_zones
      })

    socket
    |> assign(settings: settings)
    |> assign_settings_form(params)
  end

  defp assign_settings_form(socket, params) do
    assign(socket,
      mode: String.to_existing_atom(params["mode"] || "flat"),
      outside_zones: params["outside_zones"] in [true, "true"],
      settings_form: to_form(params, as: "delivery")
    )
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
    |> Map.take([:name, :color, :enabled, :delivery_minutes, :radius_km])
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

  defp error_message(:no_branch_point),
    do: gettext("Set the branch address on the map first, the radius is counted from it")

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
        title={gettext("Delivery zones")}
        subtitle={gettext("Delivery price for the site and Yandex Eda.")}
        back={~p"/staff/b/#{@current_branch}/delivery"}
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

        <div :if={@mode == :zones} class="space-y-3">
          <p class="text-sm text-base-content/60">
            {gettext(
              "The price depends on the zone of the address. Draw the zones on the map below or add a zone by radius around the branch."
            )}
          </p>
          <.input
            field={@settings_form[:show_zones]}
            type="checkbox"
            label={gettext("Show the delivery zones to customers on the address map")}
            disabled={not @can_edit}
          />
          <.input
            field={@settings_form[:outside_zones]}
            type="checkbox"
            label={gettext("Deliver outside the zones")}
            disabled={not @can_edit}
          />
          <div :if={@outside_zones} class="space-y-2 pl-7">
            <p class="text-sm text-base-content/60">
              {gettext("Conditions for addresses outside every zone.")}
            </p>
            <.conditions form={@settings_form} disabled={not @can_edit} />
          </div>
          <p :if={not @outside_zones} class="text-sm text-base-content/60 pl-7">
            {gettext(
              "Addresses outside the zones are refused, the customer sees «Sorry, we do not deliver here»."
            )}
          </p>
        </div>

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
          branch_point?={not is_nil(@branch_point.lat)}
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
  attr :stacked, :boolean, default: false

  def conditions(assigns) do
    ~H"""
    <div class={["grid gap-3", not @stacked && "sm:grid-cols-3"]}>
      <.input
        field={@form[:min_order]}
        type="text"
        inputmode="decimal"
        value={Money.input(@form[:min_order].value)}
        label={gettext("Minimum order, ₽")}
        placeholder="0"
        disabled={@disabled}
      />
      <.input
        field={@form[:price]}
        type="text"
        inputmode="decimal"
        value={Money.input(@form[:price].value)}
        label={gettext("Delivery price, ₽")}
        placeholder="0"
        disabled={@disabled}
      />
      <.input
        field={@form[:free_from]}
        type="text"
        inputmode="decimal"
        value={Money.input(@form[:free_from].value)}
        label={gettext("Free from, ₽")}
        disabled={@disabled}
      />
    </div>
    """
  end
end
