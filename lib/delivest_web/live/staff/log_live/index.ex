defmodule DelivestWeb.Staff.LogLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Audit, Logs}
  alias DelivestWeb.Staff.LogLive.{EventText, Query}
  alias DelivestWeb.Staff.LogLive.Components.{EntriesComponent, EventsComponent, TabsComponent}

  on_mount {DelivestWeb.Hooks.Permission, "logs.read"}

  @levels ~w(error warning info)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Audit.subscribe()

    {:ok, socket |> assign(page_title: gettext("Logs"), filters: %{}) |> stream(:rows, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    scope = socket.assigns.live_action
    filters = Query.filters(params)

    case fetch(scope, filters) do
      {:ok, {rows, meta}} ->
        {:noreply,
         socket
         |> assign(filters: filters, meta: meta)
         |> stream(:rows, rows, reset: true)}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: Query.path(scope, %{}))}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ~w(type level q)))
      |> Map.delete("page")
      |> Query.filters()

    {:noreply, push_patch(socket, to: Query.path(socket.assigns.live_action, filters))}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    filters = socket.assigns.filters |> Map.put("page_size", size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: Query.path(socket.assigns.live_action, filters))}
  end

  @impl true
  def handle_info({:audit_event, event}, socket) do
    if live?(socket, event),
      do: {:noreply, stream_insert(socket, :rows, event, at: 0)},
      else: {:noreply, socket}
  end

  defp fetch(:events, filters), do: Audit.list_events(Query.flop(:events, filters))
  defp fetch(scope, filters), do: Logs.list_entries(scope, Query.flop(scope, filters))

  defp live?(%{assigns: %{live_action: :events, meta: meta, filters: filters}}, event) do
    meta.current_page == 1 and filters["type"] in [nil, event.subject_type]
  end

  defp live?(_socket, _event), do: false

  @impl true
  def render(assigns) do
    assigns = assign(assigns, levels: @levels, subject_types: EventText.subject_types())

    ~H"""
    <div class="space-y-6 p-6">
      <div>
        <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Logs")}</h1>
        <p class="text-sm text-base-content/60">
          {gettext("Who did what and when, application logs, errors and hints.")}
        </p>
      </div>

      <TabsComponent.render_tabs active={@live_action} />

      <form id="logs-filter" phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-3">
        <select
          :if={@live_action == :events}
          name="type"
          class="select select-bordered w-full sm:w-56"
        >
          <option value="">{gettext("All sections")}</option>
          <option
            :for={{value, label} <- @subject_types}
            value={value}
            selected={@filters["type"] == value}
          >
            {label}
          </option>
        </select>

        <input
          :if={@live_action != :events}
          type="text"
          name="q"
          value={@filters["q"]}
          placeholder={gettext("Search in messages...")}
          class="input input-bordered w-full sm:max-w-sm"
          phx-debounce="500"
        />

        <select :if={@live_action == :raw} name="level" class="select select-bordered w-full sm:w-44">
          <option value="">{gettext("All levels")}</option>
          <option :for={level <- @levels} value={level} selected={@filters["level"] == level}>
            {level}
          </option>
        </select>
      </form>

      <EventsComponent.render_events :if={@live_action == :events} events={@streams.rows} />
      <EntriesComponent.render_entries :if={@live_action != :events} entries={@streams.rows} />

      <.pagination meta={@meta} path_fn={&Query.path(@live_action, Map.merge(@filters, &1))} />
    </div>
    """
  end
end
