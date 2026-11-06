defmodule DelivestWeb.Staff.IntegrationLive.Rkeeper do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, Rkeeper}
  alias Delivest.Integrations.Crm.{BranchSettings, StopSync}
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, JournalComponent, Presentation}

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "r_keeper",
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       token?: Rkeeper.Api.configured?(),
       tab: :settings
     )
     |> assign_settings(Crm.get_branch_settings(socket.assigns.current_branch.id))
     |> assign_context()}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(settings menu journal),
    do: {:noreply, assign(socket, tab: String.to_existing_atom(tab))}

  def handle_event("validate", %{"crm" => params}, socket) do
    changeset =
      socket.assigns.crm
      |> Crm.change_branch_settings(settings_params(params, socket.assigns))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "crm"))}
  end

  def handle_event("save", %{"crm" => params}, socket) do
    case Crm.update_branch_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           settings_params(params, socket.assigns)
         ) do
      {:ok, crm} ->
        {:noreply,
         socket
         |> assign_settings(crm)
         |> assign_context()
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :update), as: "crm"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Please check the highlighted fields"))}
    end
  end

  def handle_event("sync_stops", _params, socket) do
    case StopSync.sync(socket.assigns.current_staff, socket.assigns.current_branch.id) do
      {:ok, _result} ->
        {:noreply, put_flash(socket, :info, gettext("Stop list updated"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("r_keeper did not respond"))}
    end
  end

  defp assign_settings(socket, crm) do
    active_provider = BranchSettings.active_provider(crm)

    crm = %{
      crm
      | enabled: active_provider == :rkeeper,
        rkeeper: crm.rkeeper || %Rkeeper.Settings{}
    }

    assign(socket,
      crm: crm,
      active_provider: active_provider,
      form: to_form(Crm.change_branch_settings(crm), as: "crm")
    )
  end

  defp assign_context(socket) do
    assign(socket, context: Presentation.context(socket.assigns.current_branch.id))
  end

  defp settings_params(params, assigns) do
    provider = "rkeeper"
    submitted? = params["enabled"] in [true, "true"]
    displayed? = assigns.crm.enabled == true

    cond do
      submitted? and not displayed? ->
        params |> Map.put("enabled", "true") |> Map.put("provider", provider)

      submitted? ->
        Map.put(params, "provider", provider)

      displayed? ->
        Map.delete(params, "provider")

      true ->
        params |> Map.delete("provider") |> Map.delete("enabled")
    end
  end

  defp ready?(crm), do: Rkeeper.configured?(crm.rkeeper)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.link
        navigate={~p"/staff/b/#{@current_branch}/integrations"}
        class="btn btn-ghost btn-sm -ml-2"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title="r_keeper"
        subtitle={
          gettext("Orders go to the restaurant r_keeper POS through the White Server gateway.")
        }
      />

      <div :if={!@token?} id="rkeeper-no-token" class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{gettext("The aggregator token RKEEPER_TOKEN is not set on the server.")}</span>
      </div>

      <div role="tablist" class="tabs tabs-boxed w-fit">
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="settings"
          class={["tab", @tab == :settings && "tab-active font-bold"]}
        >
          {gettext("Settings")}
        </button>
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="menu"
          class={["tab", @tab == :menu && "tab-active font-bold"]}
        >
          {gettext("Menu")}
        </button>
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="journal"
          class={["tab", @tab == :journal && "tab-active font-bold"]}
        >
          {gettext("Request journal")}
        </button>
      </div>

      <.live_component
        :if={@tab == :settings}
        module={HealthComponent}
        id="rkeeper-health"
        provider={:rkeeper}
        branch_id={@current_branch.id}
        staff={@current_staff}
        context={@context}
      />

      <.form
        :if={@tab == :settings}
        for={@form}
        id="rkeeper-settings"
        phx-change="validate"
        phx-submit="save"
        class="rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <fieldset disabled={!@can_edit} class="space-y-4">
          <.input field={@form[:enabled]} type="checkbox" label={gettext("Send orders to r_keeper")} />
          <p
            :if={@active_provider && @active_provider != :rkeeper}
            id="rkeeper-provider-switch"
            class="text-xs text-warning"
          >
            {gettext(
              "Orders are now sent to %{crm}. Turning this on will switch sending to r_keeper.",
              crm: Crm.provider_name(@active_provider)
            )}
          </p>

          <.input
            field={@form[:menu_source]}
            type="select"
            label={gettext("Menu source")}
            options={[{gettext("Ours, the CRM is only checked"), "own"}, {"r_keeper", "crm"}]}
          />

          <.inputs_for :let={rk} field={@form[:rkeeper]}>
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={rk[:object_id]}
                type="text"
                inputmode="numeric"
                label={gettext("Restaurant objectId")}
              />
              <.input field={rk[:sandbox]} type="checkbox" label={gettext("Test gateway")} />
            </div>
            <p class="-mt-2 text-xs text-base-content/60">
              {gettext(
                "The restaurant connects us as an aggregator in its WS r_keeper and tells the objectId."
              )}
            </p>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={rk[:delivery_category_code]}
                type="text"
                label={gettext("Delivery order category")}
              />
              <.input
                field={rk[:delivery_type_code]}
                type="text"
                label={gettext("Delivery order type")}
              />
              <.input
                field={rk[:pickup_category_code]}
                type="text"
                label={gettext("Pickup order category")}
              />
              <.input field={rk[:pickup_type_code]} type="text" label={gettext("Pickup order type")} />
              <.input
                field={rk[:prepay_currency]}
                type="text"
                label={gettext("Prepayment currency GUID")}
              />
              <.input field={rk[:void_reason_code]} type="text" label={gettext("Cancel reason code")} />
            </div>

            <.input
              field={rk[:sync_stops]}
              type="checkbox"
              label={gettext("Take the stop list from r_keeper")}
            />
          </.inputs_for>

          <div class="flex flex-wrap gap-2">
            <button class="btn btn-primary">{gettext("Save")}</button>
            <button
              :if={ready?(@crm) and @crm.rkeeper.sync_stops}
              type="button"
              phx-click="sync_stops"
              class="btn"
            >
              {gettext("Update the stop list")}
            </button>
          </div>
        </fieldset>
      </.form>

      <.live_component
        :if={@tab == :menu}
        module={DelivestWeb.Staff.IntegrationLive.MenuImportComponent}
        id="rkeeper-menu"
        branch_id={@current_branch.id}
        staff={@current_staff}
        can_edit={@can_edit}
      />

      <.live_component
        :if={@tab == :journal}
        module={JournalComponent}
        id="rkeeper-journal"
        provider={:rkeeper}
        branch_id={@current_branch.id}
      />
    </div>
    """
  end
end
