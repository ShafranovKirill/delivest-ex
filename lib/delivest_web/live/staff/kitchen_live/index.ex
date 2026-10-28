defmodule DelivestWeb.Staff.KitchenLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.LocalTime
  alias Delivest.Oms.{Kitchen, Orders}
  alias DelivestWeb.KitchenPresence
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @tick :timer.seconds(15)
  @highlight :timer.seconds(10)

  @impl true
  def mount(_params, _session, socket) do
    branch = socket.assigns.current_branch

    if connected?(socket) do
      Orders.subscribe(branch.id)
      Kitchen.subscribe(branch.id)
      KitchenPresence.track_screen(self(), branch.id, socket.assigns.current_staff)
      :timer.send_interval(@tick, :tick)
    end

    {:ok,
     socket
     |> assign(page_title: gettext("Kitchen"), fresh: MapSet.new(), tickets: [])
     |> load()}
  end

  @impl true
  def handle_event("ready", %{"id" => id}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Kitchen.mark_ready(staff, branch.id, id) do
        {:ok, _order} -> socket
        {:error, :forbidden} -> put_flash(socket, :error, gettext("Permission denied"))
        {:error, _reason} -> put_flash(socket, :error, gettext("Failed to update the order"))
      end

    {:noreply, load(socket)}
  end

  def handle_event("undo", %{"id" => id}, socket) do
    %{current_staff: staff, current_branch: branch} = socket.assigns

    socket =
      case Kitchen.undo_ready(staff, branch.id, id) do
        :ok -> socket
        {:error, :too_late} -> put_flash(socket, :error, gettext("The order is already ready"))
        {:error, _reason} -> put_flash(socket, :error, gettext("Permission denied"))
      end

    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({Orders, _event, _order}, socket), do: {:noreply, load(socket)}
  def handle_info({:kitchen_changed, _branch_id}, socket), do: {:noreply, load(socket)}
  def handle_info(:tick, socket), do: {:noreply, load(socket)}

  def handle_info({:faded, ids}, socket),
    do: {:noreply, assign(socket, fresh: MapSet.difference(socket.assigns.fresh, ids))}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    branch_id = socket.assigns.current_branch.id
    now = DateTime.utc_now()

    case Kitchen.working(branch_id) do
      nil ->
        assign(socket, kitchen: nil, tickets: [], upcoming: [], pending: %{}, now: now)

      kitchen ->
        tickets = Kitchen.list_cooking(branch_id)

        socket
        |> assign(
          kitchen: kitchen,
          upcoming: Kitchen.list_upcoming(branch_id, kitchen, now),
          pending: Kitchen.pending_ready(branch_id),
          now: now
        )
        |> greet(tickets)
        |> assign(tickets: tickets)
    end
  end

  defp greet(%{assigns: %{loaded: true}} = socket, tickets) do
    known = MapSet.new(socket.assigns.tickets, & &1.order.id)
    arrived = tickets |> MapSet.new(& &1.order.id) |> MapSet.difference(known)

    if MapSet.size(arrived) == 0 do
      socket
    else
      Process.send_after(self(), {:faded, arrived}, @highlight)

      socket
      |> assign(fresh: MapSet.union(socket.assigns.fresh, arrived))
      |> push_event("kitchen:new", %{})
    end
  end

  defp greet(socket, _tickets), do: assign(socket, loaded: connected?(socket))

  @impl true
  def render(assigns) do
    ~H"""
    <div id="kitchen-screen" phx-hook="KitchenScreen" class="group flex min-h-screen flex-col">
      <div
        id="kitchen-offline"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: "#kitchen-offline")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#kitchen-offline")}
        class="fixed inset-0 z-50 flex items-center justify-center bg-error p-8 text-center text-4xl font-black text-error-content"
      >
        {gettext("No connection — new orders will not arrive")}
      </div>

      <header class="flex items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 py-3">
        <div class="flex items-baseline gap-3">
          <h1 class="text-2xl font-black">{gettext("Kitchen")}</h1>
          <span class="text-base-content/60">{@current_branch.name}</span>
        </div>
        <div class="flex items-center gap-3">
          <span class="font-mono text-2xl font-bold">{clock(@now)}</span>
          <button
            id="kitchen-start"
            type="button"
            data-kitchen-start
            class="btn btn-primary group-data-fullscreen:hidden"
          >
            <.icon name="hero-arrows-pointing-out" class="size-5" /> {gettext("Full screen")}
          </button>
        </div>
      </header>

      <div :if={is_nil(@kitchen)} class="flex flex-1 items-center justify-center p-8 text-center">
        <p id="kitchen-off" class="max-w-xl text-2xl text-base-content/60">
          {gettext(
            "The kitchen screen is off for this branch. Turn on «Kitchen works» in the branch settings."
          )}
        </p>
      </div>

      <div :if={@kitchen} class="flex flex-1 gap-4 p-4">
        <section class="flex-1">
          <p
            :if={@tickets == []}
            id="kitchen-empty"
            class="py-24 text-center text-3xl text-base-content/40"
          >
            {gettext("No orders to cook")}
          </p>

          <div id="kitchen-tickets" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <.ticket
              :for={ticket <- @tickets}
              ticket={ticket}
              now={@now}
              fresh={MapSet.member?(@fresh, ticket.order.id)}
              pending={Map.has_key?(@pending, ticket.order.id)}
            />
          </div>
        </section>

        <aside id="kitchen-upcoming" class="hidden w-56 shrink-0 md:block">
          <h2 class="mb-2 text-sm font-bold uppercase text-base-content/60">
            {gettext("Coming to the kitchen")}
          </h2>
          <p :if={@upcoming == []} class="text-sm text-base-content/40">{gettext("Nothing soon")}</p>
          <ul class="space-y-2">
            <li
              :for={%{order: order, sends_at: sends_at} <- @upcoming}
              id={"upcoming-#{order.id}"}
              class="flex items-baseline justify-between rounded-box bg-base-100 px-3 py-2"
            >
              <span class="font-bold">#{order.number}</span>
              <span class="font-mono text-base-content/70">{clock(sends_at)}</span>
            </li>
          </ul>
        </aside>
      </div>
    </div>
    """
  end

  attr :ticket, :map, required: true
  attr :now, DateTime, required: true
  attr :fresh, :boolean, default: false
  attr :pending, :boolean, default: false

  defp ticket(assigns) do
    assigns =
      assign(assigns,
        order: assigns.ticket.order,
        late: DateTime.compare(assigns.now, assigns.ticket.deadline) == :gt
      )

    ~H"""
    <article
      id={"ticket-#{@order.id}"}
      class={[
        "flex flex-col rounded-box border-4 bg-base-100 shadow-sm transition",
        @late && "border-error bg-error/10",
        !@late && @fresh && "border-warning animate-pulse",
        !@late && !@fresh && "border-base-300",
        @pending && "opacity-60"
      ]}
    >
      <header class={[
        "flex items-start justify-between gap-2 rounded-t-box px-4 py-3",
        @late && "bg-error text-error-content"
      ]}>
        <div>
          <p class="text-3xl font-black">#{@order.number}</p>
          <p class="text-lg font-semibold">
            {OrderHelpers.fulfillment_label(@order.fulfillment_type)}
          </p>
        </div>
        <div class="text-right">
          <p class="font-mono text-3xl font-black">{clock(@ticket.deadline)}</p>
          <p class="text-lg">
            {gettext("cooking %{minutes} min", minutes: minutes_since(@ticket.started_at, @now))}
          </p>
        </div>
      </header>

      <ul class="flex-1 space-y-1 px-4 py-3">
        <li :for={item <- @order.items} class="flex gap-3 text-2xl leading-tight">
          <span class="font-black">{item.quantity}×</span>
          <span class="flex-1">
            {item.title}
            <span :if={item.gift} class="badge badge-accent align-middle">{gettext("gift")}</span>
          </span>
        </li>
      </ul>

      <p
        :if={@order.comment not in [nil, ""]}
        class="mx-4 mb-3 rounded-box bg-warning/20 px-3 py-2 text-xl"
      >
        {@order.comment}
      </p>

      <div class="p-3">
        <button
          :if={!@pending}
          id={"ready-#{@order.id}"}
          type="button"
          phx-click="ready"
          phx-value-id={@order.id}
          class="btn btn-success btn-lg h-16 w-full text-2xl"
        >
          {gettext("Done")}
        </button>
        <div :if={@pending} class="flex items-center gap-3">
          <span class="flex-1 text-center text-2xl font-black text-success">
            {gettext("Done")} ✓
          </span>
          <button
            id={"undo-#{@order.id}"}
            type="button"
            phx-click="undo"
            phx-value-id={@order.id}
            class="btn btn-outline btn-lg h-16 text-xl"
          >
            {gettext("Undo")}
          </button>
        </div>
      </div>
    </article>
    """
  end

  defp clock(%DateTime{} = at), do: at |> LocalTime.utc_to_naive() |> Calendar.strftime("%H:%M")

  defp minutes_since(at, now), do: max(0, div(DateTime.diff(now, at), 60))
end
