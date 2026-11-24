defmodule DelivestWeb.Staff.DashboardLive.Heatmap do
  use DelivestWeb, :live_component

  alias Delivest.Analytics.OrderHeatmap
  import DelivestWeb.Staff.StatisticsLive.ReportComponents, only: [heatmap_panel: 1]

  @impl true
  def update(%{staff: staff, scope: scope} = assigns, socket) do
    changed? = socket.assigns[:scope] != scope or socket.assigns[:staff] != staff

    socket = assign(socket, assigns)

    socket =
      if changed? do
        {from, to} = OrderHeatmap.default_period(scope)

        assign(socket,
          from: Date.to_iso8601(from),
          to: Date.to_iso8601(to),
          error: nil,
          fulfillment: "all",
          branch_id: nil,
          detail: nil
        )
      else
        socket
      end

    {:ok, reload(socket)}
  end

  @impl true
  def handle_event("heatmap_filter", params, socket) do
    fulfillment =
      if params["fulfillment"] in ~w(all delivery pickup dine_in),
        do: params["fulfillment"],
        else: "all"

    allowed = Enum.map((socket.assigns.heatmap && socket.assigns.heatmap.branches) || [], & &1.id)
    branch_id = if params["heatmap_branch"] in allowed, do: params["heatmap_branch"], else: nil
    from = params["heatmap_from"] || ""
    to = params["heatmap_to"] || ""

    {:noreply,
     socket
     |> assign(from: from, to: to, fulfillment: fulfillment, branch_id: branch_id, detail: nil)
     |> reload()}
  end

  def handle_event("heatmap_detail", %{"day" => day, "hour" => hour}, %{assigns: %{heatmap: %{period: _}}} = socket) do
    with {day, ""} <- Integer.parse(to_string(day)),
         {hour, ""} <- Integer.parse(to_string(hour)),
         {:ok, rows} <-
           OrderHeatmap.detail(
             socket.assigns.staff,
             socket.assigns.scope,
             socket.assigns.heatmap.period,
             socket.assigns.fulfillment,
             day,
             hour,
             socket.assigns.branch_id
           ) do
      {:noreply, assign(socket, detail: %{day: day, hour: hour, rows: rows})}
    else
      _ -> {:noreply, assign(socket, detail: nil)}
    end
  end

  def handle_event("heatmap_detail", _, socket),
    do: {:noreply, assign(socket, detail: nil)}

  def handle_event("close_heatmap_detail", _, socket),
    do: {:noreply, assign(socket, detail: nil)}

  defp reload(socket) do
    with {:ok, from} <- Date.from_iso8601(socket.assigns.from),
         {:ok, to} <- Date.from_iso8601(socket.assigns.to),
         :ok <- OrderHeatmap.valid_period({from, to}) do
      case OrderHeatmap.read(
             socket.assigns.staff,
             socket.assigns.scope,
             {from, to},
             socket.assigns.fulfillment,
             socket.assigns.branch_id
           ) do
        {:ok, heatmap} -> assign(socket, heatmap: heatmap, error: nil)
        _ -> assign(socket, heatmap: nil, error: nil)
      end
    else
      _ ->
        assign(socket,
          heatmap: nil,
          error: gettext("Choose a range of complete Monday–Sunday weeks (up to 52 weeks)")
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.heatmap_panel
        :if={@heatmap || @error}
        heatmap={
          @heatmap ||
            %{cells: [], branches: [], period: OrderHeatmap.default_period(@scope), state: :empty}
        }
        detail={@detail}
        from={@from}
        to={@to}
        error={@error}
        fulfillment={@fulfillment}
        branch_id={@branch_id}
        network?={@scope == :network}
        target={"##{@id}"}
      />
    </div>
    """
  end
end
