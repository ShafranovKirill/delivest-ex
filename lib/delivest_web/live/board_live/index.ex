defmodule DelivestWeb.BoardLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Oms.{Orders, PickupBoard}

  @tick :timer.minutes(1)
  @highlight :timer.seconds(15)

  @impl true
  def mount(%{"token" => token}, session, socket) do
    DelivestWeb.Plugs.Locale.restore_from_session(session)

    case Identity.get_branch_by_board_token(token) do
      {:ok, branch} ->
        if connected?(socket) do
          Orders.subscribe(branch.id)
          :timer.send_interval(@tick, :tick)
        end

        {:ok,
         socket
         |> assign(page_title: gettext("Orders"), branch: branch, fresh: MapSet.new())
         |> load()}

      {:error, :not_found} ->
        raise DelivestWeb.BoardLive.NotFound
    end
  end

  @impl true
  def handle_info({Orders, _event, _order}, socket), do: {:noreply, load(socket)}
  def handle_info(:tick, socket), do: {:noreply, load(socket)}

  def handle_info({:faded, ids}, socket),
    do: {:noreply, assign(socket, fresh: MapSet.difference(socket.assigns.fresh, ids))}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    board = PickupBoard.list(socket.assigns.branch.id)

    socket
    |> greet(board.ready)
    |> assign(preparing: board.preparing, ready: board.ready)
  end

  defp greet(%{assigns: %{ready: shown}} = socket, ready) do
    arrived =
      ready
      |> MapSet.new(& &1.id)
      |> MapSet.difference(MapSet.new(shown, & &1.id))

    if MapSet.size(arrived) == 0 do
      socket
    else
      Process.send_after(self(), {:faded, arrived}, @highlight)

      socket
      |> assign(fresh: MapSet.union(socket.assigns.fresh, arrived))
      |> push_event("board:ready", %{})
    end
  end

  defp greet(socket, _ready), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div id="pickup-board" phx-hook="PickupBoard" class="group flex h-screen flex-col">
      <div
        id="board-offline"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: "#board-offline")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#board-offline")}
        class="fixed inset-0 z-50 flex items-center justify-center bg-error p-8 text-center text-4xl font-black text-error-content"
      >
        {gettext("No connection")}
      </div>

      <button
        id="board-start"
        type="button"
        data-board-start
        class="btn btn-primary btn-lg fixed bottom-6 right-6 z-40 group-data-fullscreen:hidden"
      >
        <.icon name="hero-speaker-wave" class="size-6" /> {gettext("Sound and full screen")}
      </button>

      <div class="grid flex-1 grid-cols-2 divide-x divide-base-300 overflow-hidden">
        <.column id="board-preparing" title={gettext("Being cooked")}>
          <span
            :for={order <- @preparing}
            id={"board-order-#{order.id}"}
            class="rounded-box bg-base-100 px-4 py-3 text-center font-mono text-5xl font-black text-base-content/70"
          >
            {order.number}
          </span>
        </.column>

        <.column id="board-ready" title={gettext("Ready to pick up")} accent>
          <span
            :for={order <- @ready}
            id={"board-order-#{order.id}"}
            data-fresh={MapSet.member?(@fresh, order.id)}
            class={[
              "rounded-box px-4 py-3 text-center font-mono text-6xl font-black transition-all duration-700",
              if(MapSet.member?(@fresh, order.id),
                do: "animate-pulse scale-105 bg-success text-success-content shadow-xl",
                else: "bg-success/15 text-success"
              )
            ]}
          >
            {order.number}
          </span>
        </.column>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :accent, :boolean, default: false
  slot :inner_block, required: true

  defp column(assigns) do
    ~H"""
    <section id={@id} class="flex min-h-0 flex-col">
      <h2 class={[
        "px-6 py-5 text-center text-4xl font-black uppercase tracking-wide",
        if(@accent, do: "bg-success text-success-content", else: "bg-base-300")
      ]}>
        {@title}
      </h2>
      <div class="grid content-start gap-4 overflow-hidden p-6 sm:grid-cols-2 xl:grid-cols-3">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
