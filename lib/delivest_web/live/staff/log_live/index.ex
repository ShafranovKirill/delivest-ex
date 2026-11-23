defmodule DelivestWeb.Staff.LogLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Audit, Identity, Logs}
  alias DelivestWeb.Staff.LogLive.{EventText, Query}

  alias DelivestWeb.Staff.LogLive.Components.{
    EntriesComponent,
    EventsComponent,
    TabsComponent
  }

  @levels ~w(error warning info)

  @impl true
  def mount(params, _session, socket) do
    staff = socket.assigns.current_staff
    logs? = Identity.can?(staff, "logs.read")
    data_system? = socket.assigns.live_action == :data_system

    cond do
      data_system? and not logs? and
          Enum.any?(DelivestWeb.StaffNav.settings_entries(staff, nil), &(&1.id == :data_transfer)) ->
        path =
          if is_binary(params["branch"]),
            do: "/staff/settings/data-transfer?branch=#{URI.encode_www_form(params["branch"])}",
            else: ~p"/staff/settings/data-transfer"

        {:ok, redirect(socket, to: path)}

      logs? ->
        if connected?(socket), do: Audit.subscribe()

        {:ok,
         socket
         |> assign(
           page_title: if(data_system?, do: gettext("Data and system"), else: gettext("Logs")),
           required_permission: "logs.read",
           filters: %{},
           options: nil,
           settings_scope_branch: nil
         )
         |> stream(:rows, [])}

      true ->
        destination =
          if data_system?,
            do: ~p"/staff/dashboard",
            else: DelivestWeb.StaffBranchPath.home(socket.assigns[:current_branch])

        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("errors", "You don't have permission to access this page.")
         )
         |> redirect(to: destination)}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    action = socket.assigns.live_action
    scope = if action == :data_system, do: :events, else: action
    branch = Enum.find(socket.assigns.staff_branches, &(&1.slug == params["branch"]))

    if (action == :data_system and params["branch"]) && is_nil(branch) do
      {:noreply, push_navigate(socket, to: ~p"/staff/settings/data-system")}
    else
      filter_params =
        if action == :data_system,
          do: params |> Map.delete("branch") |> Map.put("branch", params["event_branch"]),
          else: params

      filters = Query.filters(filter_params)

      case fetch(scope, filters) do
        {:ok, {rows, meta}} ->
          {:noreply,
           socket
           |> assign(filters: filters, meta: meta, settings_scope_branch: branch)
           |> load_options(scope)
           |> stream(:rows, rows, reset: true)}

        {:error, _meta} ->
          {:noreply, push_patch(socket, to: query_path(socket, %{}))}
      end
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ~w(type actor action branch sort level q)))
      |> Map.delete("page")
      |> Query.filters()

    {:noreply, push_patch(socket, to: query_path(socket, filters))}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    filters = socket.assigns.filters |> Map.put("page_size", size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: query_path(socket, filters))}
  end

  def handle_event("reset_events", _params, socket) do
    filters = Map.take(socket.assigns.filters, ["page_size"])
    {:noreply, push_patch(socket, to: query_path(socket, filters))}
  end

  def handle_event("reset_entries", _params, socket) do
    filters = Map.take(socket.assigns.filters, ["page_size"])
    {:noreply, push_patch(socket, to: query_path(socket, filters))}
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

  defp actor_path(action, filters, branch_slug),
    do: &query_path(action, filters |> Map.delete("page") |> Map.put("actor", &1), branch_slug)

  defp query_path(socket, filters) do
    query_path(
      socket.assigns.live_action,
      filters,
      socket.assigns.settings_scope_branch && socket.assigns.settings_scope_branch.slug
    )
  end

  defp query_path(:data_system, filters, branch_slug),
    do: Query.path(:data_system, filters, branch_slug)

  defp query_path(action, filters, _branch_slug), do: Query.path(action, filters)

  defp fetch(:events, filters), do: Audit.list_events(Query.flop(:events, filters))
  defp fetch(scope, filters), do: Logs.list_entries(scope, Query.flop(scope, filters))

  defp live?(%{assigns: %{live_action: action, meta: meta, filters: filters}}, event)
       when action in [:events, :data_system] do
    meta.current_page == 1 and Query.default_view?(filters) and
      filters["type"] in [nil, event.subject_type]
  end

  defp live?(_socket, _event), do: false

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={if(@live_action == :data_system, do: gettext("Data and system"), else: gettext("Logs"))}
      subtitle={gettext("Who did what and when, application logs and errors.")}
    >
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        levels: @levels,
        subject_types: EventText.subject_types(),
        events?: assigns.live_action in [:events, :data_system],
        events_path:
          if(assigns.live_action == :data_system,
            do:
              query_path(
                :data_system,
                %{},
                assigns.settings_scope_branch && assigns.settings_scope_branch.slug
              )
          )
      )

    ~H"""
    <div id={if(@live_action == :data_system, do: "data-system-content")} class="space-y-6">
      <TabsComponent.render_tabs
        active={if(@events?, do: :events, else: @live_action)}
        staff={@current_staff}
        scope_branch={@settings_scope_branch}
        events_path={@events_path}
      />
      <form id="logs-filter" phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-3">
        <%= if @events? do %>
          <select name="type" class="select w-full sm:w-48">
            <option value="">{gettext("All sections")}</option>
            <option
              :for={{value, label} <- @subject_types}
              value={value}
              selected={@filters["type"] == value}
            >
              {label}
            </option>
          </select>

          <select name="action" class="select w-full sm:w-52">
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

          <select name="actor" class="select w-full sm:w-48">
            <option value="">{gettext("All employees")}</option>
            <option
              :for={{id, name} <- @options.actors}
              value={id}
              selected={@filters["actor"] == id}
            >
              {name}
            </option>
          </select>

          <select name="branch" class="select w-full sm:w-44">
            <option value="">{gettext("All branches")}</option>
            <option
              :for={{id, name} <- Enum.sort_by(@options.branches, &elem(&1, 1))}
              value={id}
              selected={@filters["branch"] == id}
            >
              {name}
            </option>
          </select>

          <select name="sort" class="select w-full sm:w-44">
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
          :if={!@events?}
          type="text"
          name="q"
          value={@filters["q"]}
          placeholder={gettext("Search in messages...")}
          class="input w-full sm:max-w-sm"
          phx-debounce="500"
        />

        <select :if={@live_action == :raw} name="level" class="select w-full sm:w-44">
          <option value="">{gettext("All levels")}</option>
          <option :for={level <- @levels} value={level} selected={@filters["level"] == level}>
            {level}
          </option>
        </select>
        <button
          :if={
            !@events? and
              Map.drop(@filters, ["page", "page_size"]) != %{}
          }
          type="button"
          class="btn btn-ghost"
          phx-click="reset_entries"
        >
          <.icon name="hero-x-mark" class="size-4" /> {gettext("Reset")}
        </button>
      </form>

      <EventsComponent.render_events
        :if={@events?}
        events={@streams.rows}
        branches={@options.branches}
        actor_path={
          actor_path(@live_action, @filters, @settings_scope_branch && @settings_scope_branch.slug)
        }
        staff_id={to_string(@current_staff.id)}
      />
      <EntriesComponent.render_entries
        :if={@live_action in [:raw, :errors]}
        entries={@streams.rows}
        staff_id={to_string(@current_staff.id)}
      />

      <.pagination
        meta={@meta}
        path_fn={
          &query_path(
            @live_action,
            Map.merge(@filters, &1),
            @settings_scope_branch && @settings_scope_branch.slug
          )
        }
        page_sizes={[25, 50, 100]}
      />
    </div>
    """
  end
end
