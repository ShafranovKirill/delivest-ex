defmodule DelivestWeb.Staff.SettingsLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents, only: [settings_navigation: 1]

  alias Delivest.{Availability, Identity}
  alias Delivest.Features.Registry
  alias DelivestWeb.StaffNav
  alias DelivestWeb.Staff.IntegrationLive.Presentation

  @filters ~w(all enabled disabled attention)

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if StaffNav.settings_entries(staff, nil) != [] do
      {:ok, assign(socket, page_title: gettext("Settings"))}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    staff = socket.assigns.current_staff
    filter = if params["filter"] in @filters, do: params["filter"], else: "all"
    branch = Enum.find(socket.assigns.staff_branches, &(&1.slug == params["branch"]))

    if params["branch"] && is_nil(branch) do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_navigate(to: ~p"/staff/settings?#{%{filter: filter}}")}
    else
      assign_rows(socket, staff, branch, filter)
    end
  end

  defp assign_rows(socket, staff, branch, filter) do
    scope = if branch, do: {:branch, branch.id}, else: :franchise

    feature_rows =
      Registry.features()
      |> Enum.map(&feature_row(&1, staff, scope))

    integration_rows =
      if Identity.can?(staff, "integrations.read") do
        context = Presentation.context(branch && branch.id)
        Enum.map(Presentation.providers(branch), &integration_row(&1, staff, branch, context))
      else
        []
      end

    rows =
      (feature_rows ++ integration_rows)
      |> Enum.filter(fn row -> filter == "all" or Atom.to_string(row.state) == filter end)

    {:noreply,
     assign(socket,
       feature_filter: filter,
       feature_rows: rows,
       settings_scope_branch: branch
     )}
  end

  defp feature_row(key, staff, scope) do
    dependencies = Registry.dependencies(key)
    enabled? = Availability.feature(key, scope).effective?
    blocked_by = Enum.filter(dependencies, &(not Availability.feature(&1, scope).effective?))

    state =
      cond do
        enabled? -> :enabled
        blocked_by != [] -> :attention
        true -> :disabled
      end

    entry = StaffNav.feature_entry(key, staff)

    %{
      kind: :feature,
      key: key,
      label: entry.label,
      state: state,
      blocked_by: Enum.map(blocked_by, &StaffNav.feature_entry(&1, staff).label),
      path: entry.path
    }
  end

  defp integration_row(provider, staff, branch, context) do
    facts = Presentation.state(provider, context)
    entry = StaffNav.integration_entry(provider, staff, branch)

    state =
      case facts.main do
        :enabled -> :enabled
        :disabled -> :disabled
        _ -> :attention
      end

    %{
      kind: :integration,
      key: "integration-#{provider}",
      label: entry.label,
      state: state,
      blocked_by: [],
      path: entry.path,
      credentials: facts.credentials.text,
      connection: facts.connection.text,
      usage: facts.usage
    }
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={gettext("Settings")} subtitle={gettext("Features and connections")} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-center" class="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
      <.settings_navigation
        variant={:sidebar}
        staff={@current_staff}
        branches={@staff_branches}
        selected={@settings_scope_branch && @settings_scope_branch.id}
        current_path={@current_path}
      />

      <section id="settings-features" class="space-y-4">
        <div>
          <h2 class="text-xl font-semibold">{gettext("Features and connections")}</h2>
          <p id="settings-scope" class="text-sm text-base-content/60">
            {if @settings_scope_branch, do: @settings_scope_branch.name, else: gettext("Network")}
          </p>
        </div>
        <nav
          id="settings-feature-filter"
          aria-label={gettext("Feature status")}
          class="flex flex-wrap gap-2"
        >
          <.link
            :for={
              {key, label} <- [
                {"all", gettext("All")},
                {"enabled", gettext("Enabled")},
                {"disabled", gettext("Disabled")},
                {"attention", gettext("Needs attention")}
              ]
            }
            id={"settings-filter-#{key}"}
            patch={
              ~p"/staff/settings?#{if(@settings_scope_branch, do: %{filter: key, branch: @settings_scope_branch.slug}, else: %{filter: key})}"
            }
            class={["btn btn-sm", @feature_filter == key && "btn-primary"]}
          >{label}</.link>
        </nav>
        <div id="settings-feature-list" class="grid gap-3 sm:grid-cols-2">
          <article
            :for={row <- @feature_rows}
            id={"feature-#{row.key}"}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <div class="flex flex-wrap items-start justify-between gap-2">
              <h3 class="min-w-0 font-semibold">{row.label}</h3>
              <span class={[
                "badge badge-sm shrink-0 whitespace-nowrap",
                row.state == :enabled && "badge-success",
                row.state == :attention && "badge-warning"
              ]}>
                {case row.state do
                  :enabled -> gettext("Enabled")
                  :disabled -> gettext("Disabled")
                  :attention -> gettext("Needs attention")
                end}
              </span>
            </div>
            <p :if={row.blocked_by != []} class="mt-2 text-sm text-base-content/60">
              {gettext("Required features are disabled: %{names}",
                names: Enum.join(row.blocked_by, ", ")
              )}
            </p>
            <p :if={row.state == :disabled} class="mt-2 text-sm text-base-content/60">
              {if row.kind == :feature,
                do: gettext("This feature is disabled in this scope."),
                else: gettext("This connection is not in use in this scope.")}
            </p>
            <p :if={row.kind == :integration} class="mt-2 text-sm text-base-content/60">
              {row.credentials} · {row.connection}
            </p>
            <DelivestWeb.Staff.IntegrationLive.StateComponents.usage_rows
              :if={row.kind == :integration}
              id={"feature-#{row.key}-usage"}
              usage={row.usage}
            />
            <.link
              :if={row.path}
              navigate={row.path}
              class="link link-primary mt-3 inline-block text-sm"
            >{gettext("Open section")}</.link>
          </article>
        </div>
      </section>
    </div>
    """
  end
end
