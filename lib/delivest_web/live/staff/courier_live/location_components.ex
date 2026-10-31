defmodule DelivestWeb.Staff.CourierLive.LocationComponents do
  use DelivestWeb, :html

  attr :at, DateTime, required: true
  attr :id, :string, default: nil

  def location_age(assigns) do
    assigns = assign(assigns, minutes: div(DateTime.diff(DateTime.utc_now(), assigns.at), 60))

    ~H"""
    <span
      id={@id}
      class={["text-xs", if(@minutes >= 5, do: "text-warning", else: "text-base-content/60")]}
    >
      {if @minutes < 1,
        do: gettext("updated just now"),
        else: ngettext("updated %{count} min ago", "updated %{count} min ago", @minutes)}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :from, :map, default: nil
  attr :to, :map, default: nil
  attr :positions, :list, default: []
  attr :courier_id, :string, default: nil
  attr :class, :string, default: "h-64"

  def couriers_map(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CouriersMap"
      phx-update="ignore"
      data-from-lat={@from && @from.latitude}
      data-from-lng={@from && @from.longitude}
      data-to-lat={@to && @to.latitude}
      data-to-lng={@to && @to.longitude}
      data-courier-id={@courier_id}
      data-positions={Jason.encode!(@positions)}
      class={["overflow-hidden rounded-box border border-base-200", @class]}
    />
    """
  end
end
