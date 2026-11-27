defmodule DelivestWeb.Staff.SettingsLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.FoundationComponents, only: [form_section: 1]

  alias Delivest.Availability
  alias Delivest.Features.{Registry, Settings}
  alias Delivest.Integrations.StaffAccess
  alias DelivestWeb.StaffNav

  @groups [
    {"delivery", ~w(couriers)},
    {"operations", ~w(kitchen product_import event_log)},
    {"marketing", ~w(segments notifications marketing_policies stocks promotions loyalty)},
    {"analytics",
     ~w(analytics_basic analytics_funnel analytics_extended analytics_links analytics_franchise)},
    {"integrations",
     ~w(yandex_ads yandex_browser yandex_conversions yandex_ecommerce yandex_feed yandex_costs)}
  ]

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if StaffNav.settings_entries(staff, nil) != [] do
      {:ok,
       assign(socket,
         page_title: gettext("Capabilities"),
         pending: nil,
         message: nil,
         groups: @groups
       )}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    staff = socket.assigns.current_staff
    branch = Enum.find(socket.assigns.staff_branches, &(&1.slug == params["branch"]))

    if params["branch"] && is_nil(branch) do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_navigate(to: ~p"/staff/settings")}
    else
      {:noreply, socket |> assign(pending: nil) |> assign_rows(staff, branch)}
    end
  end

  defp assign_rows(socket, staff, branch) do
    scope = if branch, do: {:branch, branch.id}, else: :franchise
    admin? = Settings.authorized?(staff)

    feature_keys =
      @groups
      |> Enum.flat_map(&elem(&1, 1))
      |> Kernel.++(Enum.map(StaffAccess.providers(), &elem(&1, 1)))

    feature_rows =
      feature_keys
      |> Enum.map(&feature_row(&1, staff, scope, branch, admin?))
      |> Enum.filter(fn row ->
        if integration_permission?(row.key),
          do: admin?,
          else: admin? or row.state == :enabled
      end)

    assign(socket,
      feature_rows: feature_rows,
      settings_scope_branch: branch,
      feature_admin?: admin?
    )
  end

  defp feature_row(key, staff, scope, branch, admin?) do
    integration =
      Enum.find(StaffAccess.providers(), fn {_provider, feature} -> feature == key end)

    feature_scope = if integration, do: :franchise, else: scope
    dependencies = Registry.dependencies(key)
    availability = Availability.feature(key, feature_scope)

    blocked_by =
      Enum.filter(dependencies, &(not Availability.feature(&1, feature_scope).effective?))

    desired? =
      if integration, do: StaffAccess.allowed?(elem(integration, 0)), else: availability.desired?

    state =
      cond do
        integration && desired? -> :enabled
        integration -> :disabled
        availability.effective? -> :enabled
        desired? -> :attention
        true -> :disabled
      end

    entry =
      case integration do
        {provider, _feature} -> StaffNav.integration_entry(provider, staff, branch)
        nil -> StaffNav.feature_entry(key, staff)
      end

    %{
      key: key,
      label: entry.label,
      description:
        if(integration,
          do: gettext("Stops new integration work and hides its controls across the network."),
          else: description(key)
        ),
      group: group(key),
      state: state,
      desired?: desired?,
      blocked_by: Enum.map(blocked_by, &StaffNav.feature_entry(&1, staff).label),
      path:
        if(admin?,
          do: feature_path(key, branch, entry.path || integration_overview_path(branch)),
          else: entry.path
        )
    }
  end

  defp group(key) do
    Enum.find_value(@groups, "integrations", fn {id, features} ->
      if key in features, do: id
    end)
  end

  defp group_label("delivery"), do: gettext("Delivery")
  defp group_label("operations"), do: gettext("Operations")
  defp group_label("marketing"), do: gettext("Marketing")
  defp group_label("analytics"), do: gettext("Analytics and tracking")
  defp group_label("integrations"), do: gettext("Integrations")

  defp integration_overview_path(nil), do: ~p"/staff/integrations"
  defp integration_overview_path(branch), do: ~p"/staff/b/#{branch.slug}/integrations"

  defp feature_path("couriers", nil, _), do: nil
  defp feature_path("couriers", branch, _), do: ~p"/staff/b/#{branch.slug}/delivery/couriers"
  defp feature_path("analytics_franchise", nil, _), do: ~p"/staff/statistics"

  defp feature_path("analytics_franchise", branch, _),
    do: ~p"/staff/b/#{branch.slug}/analytics/comparison"

  defp feature_path("analytics_links", branch, _) when not is_nil(branch),
    do: ~p"/staff/b/#{branch.slug}/advertising-links"

  defp feature_path("analytics_extended", branch, _) when not is_nil(branch),
    do: ~p"/staff/b/#{branch.slug}/analytics/channels"

  defp feature_path(key, branch, _)
       when key in ~w(analytics_funnel analytics_extended analytics_links) do
    if branch, do: ~p"/staff/b/#{branch.slug}/analytics/funnel", else: ~p"/staff/statistics"
  end

  defp feature_path("segments", _, _), do: ~p"/staff/segments"
  defp feature_path("marketing_policies", _, _), do: ~p"/staff/marketing/policies"
  defp feature_path("notifications", _, _), do: ~p"/staff/marketing"

  defp feature_path(_, _, path), do: path

  defp settings_available?(row),
    do: row.state == :enabled or row.key == "couriers"

  defp integration_permission?(key),
    do: Enum.any?(StaffAccess.providers(), fn {_provider, feature} -> feature == key end)

  defp feature_label(key, staff) do
    case Enum.find(StaffAccess.providers(), fn {_provider, feature} -> feature == key end) do
      {provider, _feature} -> StaffNav.integration_entry(provider, staff, nil).label
      nil -> StaffNav.feature_entry(key, staff).label
    end
  end

  defp description("couriers"),
    do: gettext("Manage your own couriers. Order history is preserved when disabled.")

  defp description("product_import"), do: gettext("Import products from a file.")
  defp description("event_log"), do: gettext("View event and application logs.")
  defp description("analytics_basic"), do: gettext("View sales statistics.")
  defp description("stocks"), do: gettext("Show campaign banners.")
  defp description("promotions"), do: gettext("Apply discounts and promotion codes.")
  defp description("loyalty"), do: gettext("Award and redeem loyalty points.")
  defp description("kitchen"), do: gettext("Show the kitchen order display.")

  defp description("segments"), do: gettext("Group customers by conditions and order history.")
  defp description("notifications"), do: gettext("Send optional customer notifications.")
  defp description("marketing_policies"), do: gettext("Automate offers for customer groups.")

  defp description("analytics_funnel"),
    do: gettext("Track the path from viewing the menu to placing an order.")

  defp description("analytics_extended"), do: gettext("Additional sales and customer reports.")

  defp description("analytics_links"),
    do: gettext("Track advertising sources and orders from advertising links.")

  defp description("analytics_franchise"),
    do: gettext("Compare branches using extended analytics.")

  defp description("yandex_ads"), do: gettext("Connect Yandex Direct and Metrika data.")
  defp description(_), do: gettext("Optional integration capability.")

  @impl true
  def handle_event("toggle", %{"feature" => key}, socket) do
    scope = if integration_permission?(key), do: :franchise, else: scope(socket)
    row = Enum.find(socket.assigns.feature_rows, &(&1.key == key))

    if row && Settings.authorized?(socket.assigns.current_staff) do
      if row.desired? do
        case Settings.preview(socket.assigns.current_staff, key, scope) do
          {:ok, preview} ->
            {:noreply, assign(socket, pending: {key, scope, :disable, preview}, message: nil)}

          _ ->
            {:noreply, denied(socket)}
        end
      else
        {:noreply, save(socket, key, scope, true, nil)}
      end
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event(
        "confirm_enable",
        _,
        %{assigns: %{pending: {key, scope, :enable, preview}}} = socket
      ),
      do: {:noreply, save(socket, key, scope, true, preview)}

  def handle_event(
        "confirm_disable",
        _,
        %{assigns: %{pending: {key, scope, :disable, preview}}} = socket
      ),
      do: {:noreply, save(socket, key, scope, false, preview)}

  def handle_event("cancel_change", _, socket), do: {:noreply, assign(socket, pending: nil)}
  def handle_event(_, _, socket), do: {:noreply, denied(socket)}

  defp scope(socket) do
    case socket.assigns.settings_scope_branch do
      nil -> :franchise
      branch -> {:branch, branch.id}
    end
  end

  defp denied(socket) do
    socket
    |> assign(pending: nil, message: gettext("Permission denied"))
    |> reload_rows()
  end

  defp save(socket, key, scope, enabled, confirmation) do
    valid_scope? =
      if integration_permission?(key), do: scope == :franchise, else: scope == scope(socket)

    if valid_scope? and Registry.known?(key) do
      case Settings.configure(socket.assigns.current_staff, key, scope, enabled, confirmation) do
        {:ok, _} ->
          socket |> assign(pending: nil, message: gettext("Settings saved")) |> reload_rows()

        {:error, {:activation_required, preview}} ->
          socket |> reload_rows() |> assign(pending: {key, scope, :enable, preview}, message: nil)

        {:error, {:confirmation_required, preview}} ->
          socket
          |> reload_rows()
          |> assign(
            pending: {key, scope, :disable, preview},
            message: gettext("Settings changed. Review and confirm again.")
          )

        _ ->
          denied(socket)
      end
    else
      denied(socket)
    end
  end

  defp reload_rows(socket) do
    assign_rows(
      socket,
      socket.assigns.current_staff,
      socket.assigns.settings_scope_branch
    )
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Capabilities")}
      subtitle={gettext("Choose the functions your service uses")}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="settings-content" class="space-y-5">
      <section id="settings-features" class="space-y-4">
        <div>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Enable the functions your service needs, then open each section to configure it."
            )}
          </p>
        </div>
        <p class="text-sm text-base-content/60">
          {if @settings_scope_branch,
            do:
              gettext(
                "Changes apply to this branch. Required network functions are enabled together."
              ),
            else:
              gettext("Changes apply across the network. Enabled branches may resume optional work.")}
        </p>
        <p :if={@message} role="status" class="alert alert-info text-sm">{@message}</p>
        <div
          :if={@pending && @feature_admin?}
          id="feature-confirmation"
          role="dialog"
          aria-modal="true"
          aria-labelledby="feature-confirmation-title"
          class="modal modal-open"
          phx-window-keydown="cancel_change"
          phx-key="escape"
          phx-mounted={JS.focus(to: "#feature-cancel")}
          phx-remove={JS.focus(to: "#feature-toggle-#{elem(@pending, 0)}")}
        >
          <button
            type="button"
            class="modal-backdrop"
            aria-label={gettext("Cancel")}
            phx-click="cancel_change"
          />
          <.focus_wrap
            id="feature-confirmation-focus"
            class="modal-box max-w-lg border border-base-300 bg-base-100 text-base-content"
          >
            <h3 id="feature-confirmation-title" class="text-lg font-semibold">
              {if elem(@pending, 2) == :enable,
                do:
                  gettext("Enable «%{feature}»?",
                    feature: feature_label(elem(@pending, 0), @current_staff)
                  ),
                else:
                  gettext("Disable «%{feature}»?",
                    feature: feature_label(elem(@pending, 0), @current_staff)
                  )}
            </h3>
            <p class="mt-2 text-sm text-base-content/70">
              {if elem(@pending, 1) == :franchise,
                do: gettext("Scope: network"),
                else: gettext("Scope: %{branch}", branch: @settings_scope_branch.name)}
            </p>
            <p
              :if={elem(@pending, 2) == :enable && integration_permission?(elem(@pending, 0))}
              class="mt-3 text-sm"
            >
              {gettext("The integration will appear in the admin interface across the network.")}
            </p>
            <p
              :if={elem(@pending, 2) == :enable && !integration_permission?(elem(@pending, 0))}
              class="mt-3 text-sm"
            >
              {gettext(
                "Enabling this network function will also resume it for previously enabled branches: %{branches}.",
                branches: Enum.map_join(elem(@pending, 3).branches, ", ", & &1.name)
              )}
            </p>
            <p
              :if={elem(@pending, 2) == :disable && integration_permission?(elem(@pending, 0))}
              class="mt-3 text-sm"
            >
              {gettext(
                "The integration will be hidden in the admin interface. Existing connection activity will continue."
              )}
            </p>
            <p
              :if={elem(@pending, 2) == :disable && !integration_permission?(elem(@pending, 0))}
              class="mt-3 text-sm"
            >
              {gettext(
                "Disable %{feature}? New optional work will stop. Existing data is preserved.",
                feature: feature_label(elem(@pending, 0), @current_staff)
              )}
            </p>
            <p
              :if={elem(@pending, 2) == :disable && elem(@pending, 1) == :franchise}
              class="mt-2 text-sm"
            >
              {gettext("This change affects all branches in the network.")}
            </p>
            <p
              :if={elem(@pending, 2) == :disable && elem(@pending, 0) == "couriers"}
              class="mt-2 text-sm"
            >
              {gettext("Existing courier assignments remain available until completion.")}
            </p>
            <p
              :if={elem(@pending, 2) == :disable && elem(@pending, 3).features != []}
              class="mt-2 text-sm"
            >
              {gettext("Also disabled: %{features}",
                features:
                  Enum.map_join(
                    elem(@pending, 3).features,
                    ", ",
                    &feature_label(&1, @current_staff)
                  )
              )}
            </p>
            <div class="modal-action">
              <button
                id="feature-cancel"
                type="button"
                phx-click="cancel_change"
                class="btn btn-ghost"
              >{gettext("Cancel")}</button>
              <button
                id="feature-confirm"
                type="button"
                phx-click={
                  if(elem(@pending, 2) == :enable, do: "confirm_enable", else: "confirm_disable")
                }
                class={
                  if(elem(@pending, 2) == :disable, do: "btn btn-error", else: "btn btn-primary")
                }
              >{if(elem(@pending, 2) == :enable, do: gettext("Enable"), else: gettext("Disable"))}</button>
            </div>
          </.focus_wrap>
        </div>
        <.form_section
          :for={{group_id, _features} <- @groups}
          :if={Enum.any?(@feature_rows, &(&1.group == group_id))}
          id={"settings-group-#{group_id}"}
          title={group_label(group_id)}
        >
          <div class="grid gap-2 lg:grid-cols-2">
            <article
              :for={row <- Enum.filter(@feature_rows, &(&1.group == group_id))}
              id={"feature-#{row.key}"}
              class="rounded-box border border-base-300 bg-base-100 px-3 py-2.5"
            >
              <div class="flex items-start gap-3">
                <div class="min-w-0 flex-1">
                  <h3 class="text-sm font-semibold">{row.label}</h3>
                  <p class="text-xs text-base-content/65">{row.description}</p>
                </div>
                <button
                  :if={@feature_admin?}
                  id={"feature-toggle-#{row.key}"}
                  type="button"
                  role="switch"
                  aria-label={row.label}
                  aria-checked={to_string(row.desired?)}
                  phx-click="toggle"
                  phx-value-feature={row.key}
                  class={[
                    "relative inline-flex h-6 w-10 shrink-0 items-center rounded-full border transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                    row.desired? && "border-primary bg-primary",
                    !row.desired? && "border-base-300 bg-base-300"
                  ]}
                >
                  <span class={[
                    "size-4 rounded-full bg-base-100 shadow-sm transition-transform",
                    row.desired? && "translate-x-5",
                    !row.desired? && "translate-x-1"
                  ]} />
                </button>
              </div>
              <p :if={row.blocked_by != []} class="mt-1 text-xs text-base-content/70">
                {gettext("Required features are disabled: %{names}",
                  names: Enum.join(row.blocked_by, ", ")
                )}
              </p>
              <p
                :if={row.state == :attention && row.blocked_by == []}
                class="mt-1 text-xs text-base-content/70"
              >
                {gettext("Enabled here, but unavailable at the network level.")}
              </p>
              <div class="mt-1 flex flex-wrap items-center gap-2">
                <span class={[
                  "text-xs",
                  row.state == :enabled && "text-success",
                  row.state == :attention && "text-warning",
                  row.state == :disabled && "text-base-content/50"
                ]}>{case row.state do
                  :enabled -> gettext("Enabled")
                  :disabled -> gettext("Disabled")
                  :attention -> gettext("Needs attention")
                end}</span>
                <.link
                  :if={row.path && settings_available?(row)}
                  navigate={row.path}
                  class="link link-primary text-xs"
                >{gettext("Open settings")}</.link>
                <button
                  :if={row.path && !settings_available?(row)}
                  type="button"
                  disabled
                  class="text-xs text-base-content/50"
                >{gettext("Enable to open settings")}</button>
                <span
                  :if={row.key == "couriers" && is_nil(row.path)}
                  class="text-xs text-base-content/60"
                >{gettext("Select a branch to configure couriers.")}</span>
              </div>
            </article>
          </div>
        </.form_section>
      </section>
    </div>
    """
  end
end
