defmodule DelivestWeb.Staff.IntegrationLive.Recovery do
  use DelivestWeb, :live_view

  alias Delivest.Events
  alias Delivest.Integrations.Crm

  on_mount {DelivestWeb.Hooks.Permission, "orders.update"}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream_configure(:events, dom_id: &"event-#{&1.event_id}-#{&1.subscriber}")
      |> stream_configure(:commands, dom_id: &"command-#{&1.job_id}")
      |> stream_configure(:syncs, dom_id: &"sync-#{&1.id}")
      |> assign(page_title: gettext("Delivery recovery"), pending: nil)
      |> refresh()

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}

  def handle_event("choose", %{"kind" => kind, "id" => id, "action" => action} = params, socket)
      when kind in ["event", "command"] and action in ["done", "retry"] do
    pending = %{kind: kind, id: id, action: action, subscriber: params["subscriber"]}
    {:noreply, assign(socket, pending: pending)}
  end

  def handle_event("confirm", _, %{assigns: %{pending: nil}} = socket), do: {:noreply, socket}

  def handle_event("confirm", _, socket) do
    %{kind: kind, id: id, action: action, subscriber: subscriber} = socket.assigns.pending
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    result =
      case kind do
        "event" ->
          Events.resolve_delivery(staff, branch_id, id, subscriber, action)

        "command" ->
          case Integer.parse(id) do
            {job_id, ""} -> Crm.resolve_command(staff, branch_id, job_id, action)
            _ -> {:error, :invalid_job_id}
          end
      end

    socket =
      case result do
        {:ok, _} ->
          socket
          |> assign(pending: nil)
          |> refresh()
          |> put_flash(:info, gettext("Resolution saved"))

        {:error, _} ->
          socket
          |> assign(pending: nil)
          |> refresh()
          |> put_flash(:error, gettext("Resolution failed"))
      end

    {:noreply, socket}
  end

  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, pending: nil)}

  defp refresh(socket) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.current_branch.id

    case {Events.list_blocked(staff, branch_id), Crm.list_unknown_commands(staff, branch_id),
          Crm.list_unknown_syncs(staff, branch_id)} do
      {{:ok, events}, {:ok, commands}, {:ok, syncs}} ->
        socket
        |> stream(:events, events, reset: true)
        |> stream(:commands, commands, reset: true)
        |> stream(:syncs, syncs, reset: true)

      _ ->
        socket
        |> stream(:events, [], reset: true)
        |> stream(:commands, [], reset: true)
        |> stream(:syncs, [], reset: true)
        |> put_flash(:error, gettext("Permission denied"))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.link navigate={~p"/staff/b/#{@current_branch}/integrations"} class="btn btn-ghost btn-sm">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>
      <.page_header
        title={gettext("Delivery recovery")}
        subtitle={gettext("Compare the provider record before confirming or retrying a delivery.")}
      />
      <button id="recovery-refresh" type="button" phx-click="refresh" class="btn btn-outline btn-sm">
        {gettext("Refresh")}
      </button>

      <section aria-labelledby="recovery-events-title" class="space-y-3">
        <h2 id="recovery-events-title" class="text-lg font-bold">
          {gettext("Blocked event deliveries")}
        </h2>
        <div id="recovery-events" phx-update="stream" class="space-y-2">
          <div
            :for={{dom_id, delivery} <- @streams.events}
            id={dom_id}
            class="card border border-base-300 bg-base-100 p-4"
          >
            <p class="font-mono text-xs break-all">{delivery.event_id} · {delivery.subscriber}</p>
            <p class="text-sm">{gettext("Order")}: {delivery.aggregate_id}</p>
            <div class="mt-3 flex flex-wrap gap-2">
              <button
                id={"event-retry-#{dom_id}"}
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="choose"
                phx-value-kind="event"
                phx-value-id={delivery.event_id}
                phx-value-subscriber={delivery.subscriber}
                phx-value-action="retry"
              >
                {gettext("Retry after checking")}
              </button>
              <button
                id={"event-done-#{dom_id}"}
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="choose"
                phx-value-kind="event"
                phx-value-id={delivery.event_id}
                phx-value-subscriber={delivery.subscriber}
                phx-value-action="done"
              >
                {gettext("Execution confirmed")}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section aria-labelledby="recovery-syncs-title" class="space-y-3">
        <h2 id="recovery-syncs-title" class="text-lg font-bold">
          {gettext("CRM orders needing review")}
        </h2>
        <div id="recovery-syncs" phx-update="stream" class="space-y-2">
          <div
            :for={{dom_id, order} <- @streams.syncs}
            id={dom_id}
            class="card border border-base-300 bg-base-100 p-4"
          >
            <p class="font-mono text-xs break-all">{order.number} · {order.id}</p>
            <p class="text-sm">{gettext("Check the CRM before changing this order.")}</p>
            <.link
              id={"sync-open-#{order.id}"}
              navigate={~p"/staff/b/#{@current_branch}/orders/#{order.id}"}
              class="btn btn-outline btn-sm mt-3"
            >
              {gettext("Open order resolution")}
            </.link>
          </div>
        </div>
      </section>

      <section aria-labelledby="recovery-commands-title" class="space-y-3">
        <h2 id="recovery-commands-title" class="text-lg font-bold">
          {gettext("CRM commands needing review")}
        </h2>
        <div id="recovery-commands" phx-update="stream" class="space-y-2">
          <div
            :for={{dom_id, command} <- @streams.commands}
            id={dom_id}
            class="card border border-base-300 bg-base-100 p-4"
          >
            <p class="font-mono text-xs break-all">{command.job_id} · {command.order_id}</p>
            <p class="text-sm">{command.phase}</p>
            <div class="mt-3 flex flex-wrap gap-2">
              <button
                id={"command-retry-#{dom_id}"}
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="choose"
                phx-value-kind="command"
                phx-value-id={command.job_id}
                phx-value-action="retry"
              >
                {gettext("Retry after checking")}
              </button>
              <button
                id={"command-done-#{dom_id}"}
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="choose"
                phx-value-kind="command"
                phx-value-id={command.job_id}
                phx-value-action="done"
              >
                {gettext("Confirmed at provider")}
              </button>
            </div>
          </div>
        </div>
      </section>

      <div :if={@pending} id="recovery-confirm" class="alert flex flex-wrap items-center gap-3">
        <p>{gettext("Verify this exact delivery before proceeding.")}</p>
        <span class="font-mono text-xs break-all">
          {@pending.kind}: {@pending.id} {if @pending.subscriber, do: "· #{@pending.subscriber}"}
        </span>
        <span>
          {if @pending.action == "done",
            do: gettext("Mark execution confirmed"),
            else: gettext("Retry after checking")}
        </span>
        <button
          id="recovery-confirm-button"
          type="button"
          phx-click="confirm"
          class="btn btn-primary btn-sm"
        >
          {if @pending.action == "done",
            do: gettext("Confirm execution"),
            else: gettext("Confirm retry")}
        </button>
        <button
          id="recovery-cancel-button"
          type="button"
          phx-click="cancel"
          class="btn btn-ghost btn-sm"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end
end
