defmodule DelivestWeb.Staff.LogLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Audit, Identity, Logs}
  alias DelivestWeb.Staff.LogLive.{EventText, Query}

  alias DelivestWeb.Staff.LogLive.Components.{
    EntriesComponent,
    EventsComponent,
    HintsComponent,
    TabsComponent
  }

  on_mount {DelivestWeb.Hooks.Permission, "logs.read"}

  @levels ~w(error warning info)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Audit.subscribe()

    {:ok,
     socket
     |> assign(page_title: gettext("Logs"), filters: %{}, options: nil)
     |> stream(:rows, [])}
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
         |> load_options(scope)
         |> stream(:rows, rows, reset: true)}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: Query.path(scope, %{}))}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ~w(type actor action branch sort level q)))
      |> Map.delete("page")
      |> Query.filters()

    {:noreply, push_patch(socket, to: Query.path(socket.assigns.live_action, filters))}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    filters = socket.assigns.filters |> Map.put("page_size", size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: Query.path(socket.assigns.live_action, filters))}
  end

  def handle_event("reset_events", _params, socket) do
    filters = Map.take(socket.assigns.filters, ["page_size"])
    {:noreply, push_patch(socket, to: Query.path(:events, filters))}
  end

  @impl true
  def handle_info({:audit_event, event}, socket) do
    if live?(socket, event),
      do: {:noreply, stream_insert(socket, :rows, event, at: 0)},
      else: {:noreply, socket}
  end

  defp load_options(%{assigns: %{options: nil}} = socket, :events) do
    branches = Map.new(Identity.list_branches(), &{&1.id, &1.name})

    assign(socket,
      options: %{
        actors: Audit.list_staff_actors(),
        actions: EventText.action_groups(Audit.list_actions()),
        branches: branches
      }
    )
  end

  defp load_options(socket, _scope), do: socket

  defp sort_options do
    [
      {gettext("Newest first"), ""},
      {gettext("Oldest first"), "oldest"},
      {gettext("By employee"), "actor"},
      {gettext("By event"), "action"},
      {gettext("By branch"), "branch"}
    ]
  end

  defp actor_path(filters),
    do: &Query.path(:events, filters |> Map.delete("page") |> Map.put("actor", &1))

  defp fetch(:events, filters), do: Audit.list_events(Query.flop(:events, filters))
  defp fetch(scope, filters), do: Logs.list_entries(scope, Query.flop(scope, filters))

  defp live?(%{assigns: %{live_action: :events, meta: meta, filters: filters}}, event) do
    meta.current_page == 1 and Query.default_view?(filters) and
      filters["type"] in [nil, event.subject_type]
  end

  defp live?(_socket, _event), do: false

  @impl true
  def render(assigns) do
    assigns = assign(assigns, levels: @levels, subject_types: EventText.subject_types())

    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Logs")}
        subtitle={gettext("Who did what and when, application logs, errors and hints.")}
      />

      <TabsComponent.render_tabs active={@live_action} />

      <form id="logs-filter" phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-3">
        <%= if @live_action == :events do %>
          <select name="type" class="select select-bordered w-full sm:w-48">
            <option value="">{gettext("All sections")}</option>
            <option
              :for={{value, label} <- @subject_types}
              value={value}
              selected={@filters["type"] == value}
            >
              {label}
            </option>
          </select>

          <select name="action" class="select select-bordered w-full sm:w-52">
            <option value="">{gettext("All events")}</option>
            <optgroup :for={{section, actions} <- @options.actions} label={section}>
              <option
                :for={{label, value} <- actions}
                value={value}
                selected={@filters["action"] == value}
              >
                {label}
              </option>
            </optgroup>
          </select>

          <select name="actor" class="select select-bordered w-full sm:w-48">
            <option value="">{gettext("All employees")}</option>
            <option
              :for={{id, name} <- @options.actors}
              value={id}
              selected={@filters["actor"] == id}
            >
              {name}
            </option>
          </select>

          <select name="branch" class="select select-bordered w-full sm:w-44">
            <option value="">{gettext("All branches")}</option>
            <option
              :for={{id, name} <- Enum.sort_by(@options.branches, &elem(&1, 1))}
              value={id}
              selected={@filters["branch"] == id}
            >
              {name}
            </option>
          </select>

          <select name="sort" class="select select-bordered w-full sm:w-44">
            {Phoenix.HTML.Form.options_for_select(sort_options(), @filters["sort"] || "")}
          </select>

          <button
            :if={Map.drop(@filters, ["page", "page_size"]) != %{}}
            type="button"
            class="btn btn-ghost"
            phx-click="reset_events"
          >
            <.icon name="hero-x-mark" class="size-4" /> {gettext("Reset")}
          </button>
        <% end %>

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

      <EventsComponent.render_events
        :if={@live_action == :events}
        events={@streams.rows}
        branches={@options.branches}
        actor_path={actor_path(@filters)}
      />
      <EntriesComponent.render_entries
        :if={@live_action in [:raw, :errors]}
        entries={@streams.rows}
      />
      <HintsComponent.render_hints :if={@live_action == :hints} entries={@streams.rows} />

      <.pagination meta={@meta} path_fn={&Query.path(@live_action, Map.merge(@filters, &1))} />
    </div>
    """
  end
end
