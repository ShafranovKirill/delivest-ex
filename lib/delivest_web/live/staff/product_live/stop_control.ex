defmodule DelivestWeb.Staff.ProductLive.StopControl do
  use DelivestWeb, :html

  alias Delivest.Integrations.Crm
  alias Delivest.Net.ProductStop
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :product, :map, required: true
  attr :stops, :list, required: true
  attr :can_edit, :boolean, required: true
  attr :menu, :boolean, default: false
  attr :show_actions, :boolean, default: true
  attr :popover_id, :string, default: nil

  def stop_control(assigns) do
    assigns =
      assign(assigns,
        manual: Enum.find(assigns.stops, &ProductStop.manual?/1),
        external: Enum.reject(assigns.stops, &ProductStop.manual?/1)
      )

    ~H"""
    <div
      id={if @menu, do: "product-stop-actions-#{@product.id}", else: "product-stop-#{@product.id}"}
      class={if @menu, do: "flex flex-col", else: "flex flex-wrap items-center gap-1"}
    >
      <span
        :for={stop <- @external}
        :if={not @menu}
        class="badge badge-warning badge-sm whitespace-nowrap"
        title={gettext("Lifted in %{crm}", crm: crm_name(stop.source))}
      >
        {gettext("Stop in %{crm}", crm: crm_name(stop.source))}
      </span>

      <span
        :if={@manual && not @menu}
        class="badge badge-error badge-sm whitespace-nowrap"
        title={author(@manual)}
      >
        {until_label(@manual)}
      </span>

      <button
        :if={@manual && @can_edit && @show_actions}
        type="button"
        class={
          if @menu,
            do: "w-full rounded-field px-3 py-2 text-start text-sm hover:bg-base-200",
            else: "btn btn-ghost btn-xs"
        }
        phx-click="resume"
        phx-value-id={@product.id}
        popovertarget={@popover_id}
      >
        {gettext("Lift")}
      </button>

      <div
        :if={is_nil(@manual) && @can_edit && @show_actions && @menu}
        class="border-t border-base-300 pt-1"
      >
        <p class="px-3 py-1 text-xs font-semibold text-base-content/60">{gettext("Stop")}</p>
        <button
          type="button"
          class="w-full rounded-field px-3 py-2 text-start text-sm hover:bg-base-200"
          phx-click="stop"
          phx-value-id={@product.id}
          phx-value-period="today"
          popovertarget={@popover_id}
        >{gettext("Until end of day")}</button>
        <button
          type="button"
          class="w-full rounded-field px-3 py-2 text-start text-sm hover:bg-base-200"
          phx-click="stop"
          phx-value-id={@product.id}
          phx-value-period="until_resumed"
          popovertarget={@popover_id}
        >{gettext("Until lifted")}</button>
      </div>

      <div
        :if={is_nil(@manual) && @can_edit && @show_actions && not @menu}
        class="dropdown dropdown-end"
      >
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
