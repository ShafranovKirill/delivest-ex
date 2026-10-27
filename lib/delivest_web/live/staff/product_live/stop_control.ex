defmodule DelivestWeb.Staff.ProductLive.StopControl do
  use DelivestWeb, :html

  alias Delivest.Integrations.Crm
  alias Delivest.Net.ProductStop
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :product, :map, required: true
  attr :stops, :list, required: true
  attr :can_edit, :boolean, required: true

  def stop_control(assigns) do
    assigns =
      assign(assigns,
        manual: Enum.find(assigns.stops, &ProductStop.manual?/1),
        external: Enum.reject(assigns.stops, &ProductStop.manual?/1)
      )

    ~H"""
    <div id={"product-stop-#{@product.id}"} class="flex flex-wrap items-center gap-1">
      <span
        :for={stop <- @external}
        class="badge badge-warning badge-sm whitespace-nowrap"
        title={gettext("Lifted in %{crm}", crm: crm_name(stop.source))}
      >
        {gettext("Stop in %{crm}", crm: crm_name(stop.source))}
      </span>

      <span :if={@manual} class="badge badge-error badge-sm whitespace-nowrap" title={author(@manual)}>
        {until_label(@manual)}
      </span>

      <button
        :if={@manual && @can_edit}
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click="resume"
        phx-value-id={@product.id}
      >
        {gettext("Lift")}
      </button>

      <div :if={is_nil(@manual) && @can_edit} class="dropdown dropdown-end">
        <button type="button" tabindex="0" class="btn btn-ghost btn-xs">
          <.icon name="hero-no-symbol" class="size-4" /> {gettext("Stop")}
        </button>
        <ul tabindex="0" class="dropdown-content menu z-10 w-48 rounded-box bg-base-100 p-1 shadow">
          <li>
            <button type="button" phx-click="stop" phx-value-id={@product.id} phx-value-period="today">
              {gettext("Until end of day")}
            </button>
          </li>
          <li>
            <button
              type="button"
              phx-click="stop"
              phx-value-id={@product.id}
              phx-value-period="until_resumed"
            >
              {gettext("Until lifted")}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp until_label(%ProductStop{until: nil}), do: gettext("In stop")

  defp until_label(%ProductStop{until: until}),
    do: gettext("Stop until %{time}", time: OrderHelpers.local_time(until))

  defp author(%ProductStop{staff: %{name: name}, inserted_at: at}) when is_binary(name),
    do: "#{name}, #{OrderHelpers.local_datetime(at)}"

  defp author(%ProductStop{inserted_at: at}), do: OrderHelpers.local_datetime(at)

  defp crm_name(source) do
    case Crm.provider_name(source) do
      {:error, _reason} -> source
      name -> name
    end
  end
end
