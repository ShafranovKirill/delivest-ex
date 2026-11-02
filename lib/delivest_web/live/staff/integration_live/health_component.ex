defmodule DelivestWeb.Staff.IntegrationLive.HealthComponent do
  use DelivestWeb, :live_component

  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Health.Status
  alias DelivestWeb.Staff.IntegrationLive.{Presentation, StateComponents}

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(
        state: Presentation.state(assigns.provider, assigns.branch),
        checkable?: Health.checkable?(assigns.provider)
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("check", _params, socket) do
    case Health.check(socket.assigns.provider, socket.assigns.branch_id) do
      {:ok, %Status{}} ->
        {:noreply,
         assign(socket, state: Presentation.state(socket.assigns.provider, socket.assigns.branch))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <StateComponents.summary id={"#{@id}-summary"} state={@state} branch={@branch}>
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
