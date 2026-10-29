defmodule DelivestWeb.Staff.DeliveryLive.ZonePanel do
  use DelivestWeb, :html

  alias Delivest.Money
  alias Delivest.Delivery.Conditions
  alias DelivestWeb.Staff.DeliveryLive.Zones

  attr :zones, :list, required: true
  attr :selected_id, :string, default: nil
  attr :form, :any, default: nil
  attr :can_edit, :boolean, required: true
  attr :branch_point?, :boolean, default: false

  def panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <button
        :if={@can_edit}
        id="delivery-draw-zone"
        type="button"
        class="btn btn-primary btn-block"
        phx-click="draw_zone"
      >
        <.icon name="hero-pencil-square" class="size-4" />
        {gettext("Draw a zone")}
      </button>
      <p :if={@can_edit} class="text-xs text-base-content/60">
        {gettext("Click the map to put the points, click the first point to close the zone.")}
      </p>

      <form
        :if={@can_edit}
        id="delivery-radius-zone"
        phx-submit="add_radius_zone"
        class="flex items-end gap-2"
      >
        <label class="flex-1">
          <span class="label mb-1 text-sm">{gettext("Radius around the branch, km")}</span>
          <input
            type="number"
            name="radius"
            min="0.1"
            max="100"
            step="0.1"
            placeholder="5"
            required
            class="input w-full"
            disabled={not @branch_point?}
          />
        </label>
        <button type="submit" class="btn" disabled={not @branch_point?}>
          <.icon name="hero-plus" class="size-4" />
          {gettext("Add")}
        </button>
      </form>
      <p :if={@can_edit and not @branch_point?} class="text-xs text-warning">
        {gettext("Set the branch address on the map first, the radius is counted from it")}
      </p>

      <p :if={@zones == []} class="text-sm text-base-content/50 italic">
        {gettext("No zones yet, every delivery address is refused")}
      </p>

      <ul :if={@zones != []} class="space-y-1">
        <li :for={zone <- @zones}>
          <button
            id={"delivery-zone-#{zone.id}"}
            type="button"
            phx-click="select_zone"
            phx-value-id={zone.id}
            class={[
              "flex w-full items-center gap-2 rounded-box px-3 py-2 text-left text-sm transition-colors",
              zone.id == @selected_id && "bg-base-200 font-medium",
              zone.id != @selected_id && "hover:bg-base-200/60",
              not zone.enabled && "opacity-50"
            ]}
          >
            <span class="size-3 shrink-0 rounded-full" style={"background: #{zone.color}"} />
            <span class="min-w-0 flex-1 truncate">{zone.name}</span>
            <span class="text-xs text-base-content/60">{summary(zone)}</span>
          </button>
        </li>
      </ul>

      <.form
        :if={@form}
        for={@form}
        id="delivery-zone-form"
        phx-submit="save_zone"
        class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
      >
        <div class="space-y-3">
          <.input field={@form[:name]} type="text" label={gettext("Name")} disabled={not @can_edit} />
          <.input
            field={@form[:color]}
            type="color"
            label={gettext("Color")}
            disabled={not @can_edit}
          />
        </div>
        <.input
          :if={@form[:radius_km].value}
          field={@form[:radius_km]}
          type="number"
          min="0.1"
          max="100"
          step="0.1"
          label={gettext("Radius around the branch, km")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("Delivers")}
          disabled={not @can_edit}
        />
        <Zones.conditions form={@form} disabled={not @can_edit} stacked />
        <.input
          field={@form[:delivery_minutes]}
          type="number"
          min="1"
          label={gettext("Delivery time, min")}
          disabled={not @can_edit}
        />
        <div :if={@can_edit} class="flex justify-between gap-2">
          <button
            type="button"
            class="btn btn-ghost btn-sm text-error"
            phx-click="delete_zone"
            phx-value-id={@selected_id}
            data-confirm={gettext("Delete the zone?")}
          >
            <.icon name="hero-trash" class="size-4" />
            {gettext("Delete")}
          </button>
          <button type="submit" class="btn btn-primary btn-sm" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp summary(zone) do
    conditions = Conditions.from_thresholds(zone.thresholds)

    [
      price(conditions["price"]),
      conditions["min_order"] &&
        gettext("from %{sum}", sum: Money.format(conditions["min_order"]))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp price(price) when price in [nil, 0], do: gettext("free")
  defp price(price), do: Money.format(price)
end
