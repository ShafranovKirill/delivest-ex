defmodule DelivestWeb.Staff.SettingsLive.AnalyticsComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Features, Identity}
  alias Delivest.Features.Settings

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(pending: nil, message: nil) |> load()}
  end

  defp load(socket) do
    authorized = Settings.authorized?(socket.assigns.current_staff)
    scope = socket.assigns.scope

    rows =
      if authorized do
        if scope == :franchise do
          [
            %{
              feature: "analytics_franchise",
              scope: :franchise,
              name: gettext("Network analytics")
            }
            | Enum.map(
                Identity.list_branch_for_staff(
                  Identity.fresh_staff(socket.assigns.current_staff)
                ),
                fn b ->
                  %{feature: "analytics_franchise", scope: {:branch, b.id}, name: b.name}
                end
              )
          ]
        else
          Enum.map(Settings.branch_features(), &%{feature: &1, scope: scope, name: nil})
        end
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          Map.merge(row, %{index: index, enabled: Features.enabled?(row.feature, row.scope)})
        end)
      else
        []
      end

    assign(socket, authorized: authorized, rows: rows)
  end

  @impl true
  def handle_event("toggle", %{"row" => index}, socket) do
    row = Enum.find(socket.assigns.rows, &(Integer.to_string(&1.index) == index))

    if row && Settings.authorized?(socket.assigns.current_staff) do
      if row.enabled do
        case Settings.preview(socket.assigns.current_staff, row.feature, row.scope) do
          {:ok, preview} -> {:noreply, assign(socket, pending: {row, preview}, message: nil)}
          _ -> {:noreply, denied(socket)}
        end
      else
        {:noreply, save(socket, row, true, nil)}
      end
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event(
        "confirm_enable",
        _,
        %{assigns: %{pending: {row, %{branches: _} = preview}}} = socket
      ),
      do: {:noreply, save(socket, row, true, preview)}

  def handle_event(
        "confirm_disable",
        _,
        %{assigns: %{pending: {row, %{features: _} = preview}}} = socket
      ),
      do: {:noreply, save(socket, row, false, preview)}

  def handle_event("confirm_disable", _, socket), do: {:noreply, denied(socket)}
  def handle_event("cancel_disable", _, socket), do: {:noreply, assign(socket, pending: nil)}
  def handle_event(_, _, socket), do: {:noreply, denied(socket)}

  defp denied(socket),
    do: socket |> assign(message: gettext("Permission denied"), pending: nil) |> load()

  defp save(socket, row, enabled, preview) do
    case Settings.configure(
           socket.assigns.current_staff,
           row.feature,
           row.scope,
           enabled,
           preview
         ) do
      {:ok, _} ->
        socket |> assign(pending: nil, message: gettext("Settings saved")) |> load()

      {:error, {:activation_required, preview}} ->
        socket |> load() |> assign(pending: {row, preview}, message: nil)

      {:error, {:confirmation_required, preview}} ->
        socket
        |> load()
        |> assign(
          pending: {row, preview},
          message: gettext("Settings changed. Review and confirm again.")
        )

      _ ->
        denied(socket)
    end
  end

  defp label("segments"), do: gettext("Customer segments")
  defp label("analytics_funnel"), do: gettext("Sales funnel")
  defp label("analytics_extended"), do: gettext("Extended analytics")
  defp label("analytics_links"), do: gettext("Advertising links")
  defp label("analytics_franchise"), do: gettext("Network analytics")
  defp label("marketing_policies"), do: gettext("Marketing policies")
  defp label(feature), do: feature

  defp description("segments"),
    do:
      gettext(
        "Group customers by conditions and order history. Segments are shared across the network."
      )

  defp description("analytics_funnel"),
    do: gettext("Track the path from viewing the menu to placing an order.")

  defp description("analytics_extended"), do: gettext("Additional sales and customer reports.")

  defp description("analytics_links"),
    do: gettext("Track advertising sources and orders from advertising links.")

  defp description("analytics_franchise"),
    do:
      gettext(
        "Compare branches with extended analytics. Basic network sales statistics are always available to staff with network statistics access."
      )

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="space-y-5">
      <p :if={!@authorized} class="alert alert-error">{gettext("Permission denied")}</p>
      <p :if={@message} role="status" class="text-sm">{@message}</p>
      <div :if={@authorized} class="space-y-4">
        <p :if={@scope != :franchise} class="text-sm text-base-content/70">
          {gettext(
            "Enabling a feature activates it for this branch and enables its required network modules. Changes affecting other branches require confirmation."
          )}
        </p>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Changes are saved immediately. Enabling a feature also enables its required features. Previously collected data is preserved when tracking is disabled."
          )}
        </p>
        <article
          :for={row <- @rows}
          class="flex items-start justify-between gap-4 rounded-xl border border-base-300 p-4"
        >
          <div>
            <h2 class="font-semibold">{if row.name, do: row.name, else: label(row.feature)}</h2>
            <p class="mt-1 max-w-2xl text-sm text-base-content/70">{description(row.feature)}</p>
          </div>
          <button
            id={"analytics-toggle-#{row.index}"}
            type="button"
            role="switch"
            aria-checked={to_string(row.enabled)}
            aria-label={if row.name, do: row.name, else: label(row.feature)}
            phx-click="toggle"
            phx-value-row={row.index}
            phx-target={@myself}
            class={[
              "shrink-0 rounded-full border px-4 py-2 text-sm",
              row.enabled && "bg-primary text-primary-content"
            ]}
          >
            {if row.enabled, do: gettext("Enabled"), else: gettext("Disabled")}
          </button>
        </article>
      </div>
      <div
        :if={@pending && @authorized && Map.has_key?(elem(@pending, 1), :branches)}
        id="analytics-enable-confirmation"
        role="alert"
        class="space-y-3 rounded-xl border border-warning p-4"
      >
        <p>
          {gettext(
            "The shared network module is disabled. Enabling it will also resume tracking for: %{branches}.",
            branches: Enum.map_join(elem(@pending, 1).branches, ", ", & &1.name)
          )}
        </p>
        <button
          id="analytics-confirm-enable"
          type="button"
          phx-click="confirm_enable"
          phx-target={@myself}
          class="btn btn-warning btn-sm"
        >{gettext("Enable")}</button>
        <button
          type="button"
          phx-click="cancel_disable"
          phx-target={@myself}
          class="btn btn-ghost btn-sm"
        >{gettext("Cancel")}</button>
      </div>
      <div
        :if={@pending && @authorized && Map.has_key?(elem(@pending, 1), :features)}
        id="analytics-disable-confirmation"
        role="alert"
        class="space-y-3 rounded-xl border border-warning p-4"
      >
        <p>
          {gettext(
            "Disable %{feature}? New data collection and dependent reports will stop. Existing data will be preserved.",
            feature: label(elem(@pending, 0).feature)
          )}
        </p>
        <p :if={elem(@pending, 1).features != []}>
          {gettext("Also disabled: %{features}",
            features: Enum.map_join(elem(@pending, 1).features, ", ", &label/1)
          )}
        </p>
        <button
          id="analytics-confirm-disable"
          type="button"
          phx-click="confirm_disable"
          phx-target={@myself}
          class="btn btn-warning btn-sm"
        >{gettext("Disable")}</button>
        <button
          type="button"
          phx-click="cancel_disable"
          phx-target={@myself}
          class="btn btn-ghost btn-sm"
        >{gettext("Cancel")}</button>
      </div>
    </section>
    """
  end
end
