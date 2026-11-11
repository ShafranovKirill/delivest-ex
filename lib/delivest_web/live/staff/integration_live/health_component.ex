defmodule DelivestWeb.Staff.IntegrationLive.HealthComponent do
  use DelivestWeb, :live_component

  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Health.Status
  alias DelivestWeb.Staff.IntegrationLive.{Presentation, StateComponents}

  @impl true
  def update(assigns, socket) do
    current = socket.assigns[:context]

    if current && current.version == assigns.context.version do
      # The parent re-rendered the form only. Keep the last check result and do
      # not read the saved settings again until a fresh context arrives.
      {:ok, assign(socket, assigns)}
    else
      {:ok, socket |> assign(assigns) |> assign_status()}
    end
  end

  @impl true
  def handle_event("check", _params, socket) do
    case Health.check_as(socket.assigns.staff, socket.assigns.provider, socket.assigns.branch_id) do
      {:ok, %Status{}} ->
        context = refresh_health(socket.assigns.context, socket.assigns.branch_id)
        {:noreply, assign(socket, state: Presentation.state(socket.assigns.provider, context))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp assign_status(socket) do
    assigns = socket.assigns

    assign(socket,
      state: Presentation.state(assigns.provider, assigns.context),
      checkable?: Health.checkable_for?(assigns.staff, assigns.provider, assigns.branch_id)
    )
  end

  defp refresh_health(context, nil),
    do: %{context | health: Presentation.context(nil).health}

  defp refresh_health(context, branch_id),
    do: %{context | health: Health.for_branch(branch_id)}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <StateComponents.summary id={"#{@id}-summary"} state={@state} branch={@context.branch}>
        <:action>
          <button
            :if={@checkable?}
            id={"#{@id}-check"}
            type="button"
            class="btn btn-sm"
            phx-click="check"
            phx-target={@myself}
            phx-disable-with={gettext("Checking...")}
          >
            <.icon name="hero-signal" class="size-4" /> {gettext("Check the connection")}
          </button>
        </:action>
      </StateComponents.summary>
    </div>
    """
  end
end
