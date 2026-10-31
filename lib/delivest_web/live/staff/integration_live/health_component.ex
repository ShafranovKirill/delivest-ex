defmodule DelivestWeb.Staff.IntegrationLive.HealthComponent do
  use DelivestWeb, :live_component

  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Health.Status
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, assign(socket, status: Health.get(assigns.provider, assigns.scope))}
  end

  @impl true
  def handle_event("check", _params, socket) do
    case Health.check(socket.assigns.provider, socket.assigns.branch_id) do
      {:ok, %Status{} = status} -> {:noreply, assign(socket, status: status)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-base-300 bg-base-100 p-4"
    >
      <div class="flex min-w-0 items-center gap-3">
        <.status_icon status={@status && @status.status} />
        <div class="min-w-0">
          <div class="font-semibold">{status_text(@status)}</div>
          <div :if={@status} class="truncate text-xs text-base-content/60">
            {gettext("Checked")}: {OrderHelpers.local_datetime(@status.checked_at)}
            <span :if={@status.message}>· {@status.message}</span>
          </div>
        </div>
      </div>
      <button
        id={"#{@id}-check"}
        type="button"
        class="btn btn-sm"
        phx-click="check"
        phx-target={@myself}
        phx-disable-with={gettext("Checking...")}
      >
        <.icon name="hero-signal" class="size-4" /> {gettext("Check the connection")}
      </button>
    </section>
    """
  end

  attr :status, :atom, default: nil

  defp status_icon(%{status: :ok} = assigns),
    do: ~H|<.icon name="hero-check-circle" class="size-6 shrink-0 text-success" />|

  defp status_icon(%{status: :auth} = assigns),
    do: ~H|<.icon name="hero-key" class="size-6 shrink-0 text-error" />|

  defp status_icon(%{status: :failed} = assigns),
    do: ~H|<.icon name="hero-exclamation-triangle" class="size-6 shrink-0 text-warning" />|

  defp status_icon(%{status: :warning} = assigns),
    do: ~H|<.icon name="hero-exclamation-triangle" class="size-6 shrink-0 text-warning" />|

  defp status_icon(assigns),
    do:
      ~H|<.icon name="hero-question-mark-circle" class="size-6 shrink-0 text-base-content/40" />|

  defp status_text(nil), do: gettext("The connection has not been checked")
  defp status_text(%Status{status: :ok}), do: gettext("Connected")

  defp status_text(%Status{status: :auth}),
    do: gettext("Access denied, reconnect the integration")

  defp status_text(%Status{status: :failed}), do: gettext("No connection")

  defp status_text(%Status{status: :warning, message: "catalog_issues:" <> count}),
    do: gettext("The menu differs from the CRM: %{count}", count: count)

  defp status_text(%Status{status: :warning, message: "reconcile_issues:" <> count}),
    do: gettext("Payments differ from YooKassa: %{count}", count: count)

  defp status_text(%Status{status: :warning}), do: gettext("Needs attention")
end
