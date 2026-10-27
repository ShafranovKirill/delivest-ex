defmodule DelivestWeb.Staff.BranchLive.LocationFields do
  use DelivestWeb, :html

  attr :form, Phoenix.HTML.Form, required: true
  attr :map, :boolean, required: true
  attr :suggestions, :list, default: []
  attr :target, :any, required: true

  def location_fields(%{map: true} = assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="relative">
        <input
          type="text"
          name="location_query"
          value=""
          phx-debounce="500"
          autocomplete="off"
          placeholder={gettext("Find the branch address")}
          class="input w-full"
        />
        <ul
          :if={@suggestions != []}
          id="location-suggestions"
          class="menu absolute z-20 mt-1 w-full rounded-box border border-base-300 bg-base-100 p-1 shadow"
        >
          <li :for={{address, index} <- Enum.with_index(@suggestions)}>
            <button
              type="button"
              phx-click="pick_location"
              phx-value-index={index}
              phx-target={@target}
            >
              {address.value}
            </button>
          </li>
        </ul>
      </div>

      <div
        id="branch-location-map"
        phx-hook="LocationMap"
        phx-update="ignore"
        phx-target={@target}
        data-lat={@form[:latitude].value}
        data-lng={@form[:longitude].value}
        class="h-80 overflow-hidden rounded-box border border-base-300"
      />
      <p class="text-xs text-base-content/60">
        {gettext("Drag the pin or click the map to set the exact point.")}
      </p>

      <div class="grid gap-4 sm:grid-cols-2">
        <.input field={@form[:city]} type="text" label={gettext("Delivery city")} />
        <.input field={@form[:address]} type="text" label={gettext("Address")} />
      </div>
      <input type="hidden" name={@form[:latitude].name} value={@form[:latitude].value} />
      <input type="hidden" name={@form[:longitude].name} value={@form[:longitude].value} />
    </div>
    """
  end

  def location_fields(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2">
      <.input
        field={@form[:city]}
        type="text"
        label={gettext("Delivery city")}
        placeholder={gettext("For example, Tyumen")}
      />
      <.input field={@form[:address]} type="text" label={gettext("Address")} />
      <.input field={@form[:latitude]} type="number" step="0.000001" label={gettext("Latitude")} />
      <.input field={@form[:longitude]} type="number" step="0.000001" label={gettext("Longitude")} />
    </div>
    """
  end
end
