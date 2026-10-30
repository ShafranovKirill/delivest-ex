defmodule DelivestWeb.Staff.IntegrationLive.Iiko do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, Iiko}
  alias Delivest.Integrations.Crm.{BranchSettings, StopSync}
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, JournalComponent}

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "iiko",
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       tab: :settings,
       organizations: [],
       terminal_groups: [],
       payment_types: []
     )
     |> assign_settings(Crm.get_branch_settings(socket.assigns.current_branch.id))}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(settings menu journal),
    do: {:noreply, assign(socket, tab: String.to_existing_atom(tab))}

  def handle_event("validate", %{"crm" => params}, socket) do
    changeset =
      socket.assigns.crm
      |> Crm.change_branch_settings(with_provider(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "crm"))}
  end

  def handle_event("save", %{"crm" => params}, socket) do
    case Crm.update_branch_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           with_provider(params)
         ) do
      {:ok, crm} ->
        {:noreply, socket |> assign_settings(crm) |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :update), as: "crm"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Please check the highlighted fields"))}
    end
  end

  def handle_event("load", _params, socket) do
    settings = socket.assigns.crm.iiko

    with {:ok, organizations} <- Iiko.organizations(settings),
         ids = Enum.map(organizations, & &1.id),
         {:ok, groups} <- Iiko.terminal_groups(settings, ids),
         {:ok, %{payment_types: types}} <- Iiko.dictionaries(settings, ids) do
      {:noreply,
       assign(socket, organizations: organizations, terminal_groups: groups, payment_types: types)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("webhooks", _params, socket) do
    case Iiko.register_webhooks(socket.assigns.crm.iiko) do
      {:ok, _body} -> {:noreply, put_flash(socket, :info, gettext("iiko will send updates"))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("sync_stops", _params, socket) do
    case StopSync.sync(socket.assigns.current_branch.id) do
      {:ok, _result} -> {:noreply, put_flash(socket, :info, gettext("Stop list updated"))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  defp assign_settings(socket, crm) do
    crm = %{crm | provider: :iiko, iiko: crm.iiko || %Iiko.Settings{}}
    assign(socket, crm: crm, form: to_form(Crm.change_branch_settings(crm), as: "crm"))
  end

  defp with_provider(params), do: Map.put(params, "provider", "iiko")

  defp api_key?(%BranchSettings{iiko: %{api_key: key}}), do: key not in [nil, ""]
  defp api_key?(_crm), do: false

  defp ready?(%BranchSettings{iiko: settings}), do: Iiko.configured?(settings)

  defp options(list, current) do
    list = Enum.map(list, &{&1.name, &1.id})

    if current in [nil, ""] or Enum.any?(list, &(elem(&1, 1) == current)),
      do: list,
      else: [{current, current} | list]
  end

  defp error_text({:iiko, _status, text}), do: gettext("iiko error: %{error}", error: text)
  defp error_text({:iiko, text}), do: gettext("iiko error: %{error}", error: text)
  defp error_text(_reason), do: gettext("iiko did not respond, try again later")

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
        title="iiko"
        subtitle={gettext("Orders go to the restaurant POS, statuses and the stop list come back.")}
      />

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
        :if={@tab == :settings and ready?(@crm)}
        module={HealthComponent}
        id="iiko-health"
        provider={:iiko}
        branch_id={@current_branch.id}
        scope={@current_branch.id}
      />

      <.form
        :if={@tab == :settings}
        for={@form}
        id="iiko-settings"
        phx-change="validate"
        phx-submit="save"
        class="rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <fieldset disabled={!@can_edit} class="space-y-4">
          <.input field={@form[:enabled]} type="checkbox" label={gettext("Send orders to iiko")} />

          <.inputs_for :let={iiko} field={@form[:iiko]}>
            <.input
              field={iiko[:api_key]}
              type="password"
              value={iiko[:api_key].value}
              label={gettext("iiko API key")}
            />
            <p class="-mt-2 text-xs text-base-content/60">
              {gettext("iikoWeb → Integrations → API keys. Save the key, then load the lists.")}
            </p>

            <button
              :if={api_key?(@crm)}
              id="iiko-load"
              type="button"
              phx-click="load"
              phx-disable-with={gettext("Loading...")}
              class="btn btn-sm"
            >
              <.icon name="hero-arrow-path" class="size-4" /> {gettext("Load from iiko")}
            </button>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={iiko[:organization_id]}
                type="select"
                prompt={gettext("Choose")}
                label={gettext("Organization")}
                options={options(@organizations, iiko[:organization_id].value)}
              />
              <.input
                field={iiko[:terminal_group_id]}
                type="select"
                prompt={gettext("Choose")}
                label={gettext("Terminal group")}
                options={options(@terminal_groups, iiko[:terminal_group_id].value)}
              />
            </div>

            <p class="text-sm font-medium">{gettext("Payment types in iiko")}</p>
            <div class="grid gap-4 sm:grid-cols-3">
              <.input
                field={iiko[:cash_payment_type_id]}
                type="select"
                prompt={gettext("Choose")}
                label={gettext("Cash")}
                options={options(@payment_types, iiko[:cash_payment_type_id].value)}
              />
              <.input
                field={iiko[:card_payment_type_id]}
                type="select"
                prompt={gettext("Choose")}
                label={gettext("Card")}
                options={options(@payment_types, iiko[:card_payment_type_id].value)}
              />
              <.input
                field={iiko[:online_payment_type_id]}
                type="select"
                prompt={gettext("Choose")}
                label={gettext("Online")}
                options={options(@payment_types, iiko[:online_payment_type_id].value)}
              />
            </div>

            <.input
              field={iiko[:sync_stops]}
              type="checkbox"
              label={gettext("Take the stop list from iiko")}
            />
          </.inputs_for>

          <div class="flex flex-wrap gap-2">
            <button class="btn btn-primary">{gettext("Save")}</button>
            <button
              :if={ready?(@crm)}
              id="iiko-webhooks"
              type="button"
              phx-click="webhooks"
              class="btn"
            >
              {gettext("Connect iiko updates")}
            </button>
            <button
              :if={ready?(@crm) and @crm.iiko.sync_stops}
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
        id="iiko-menu"
        branch_id={@current_branch.id}
        staff={@current_staff}
        can_edit={@can_edit}
      />

      <.live_component
        :if={@tab == :journal}
        module={JournalComponent}
        id="iiko-journal"
        provider={:iiko}
        branch_id={@current_branch.id}
      />
    </div>
    """
  end
end
