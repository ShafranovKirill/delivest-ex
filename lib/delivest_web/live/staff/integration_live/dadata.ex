defmodule DelivestWeb.Staff.IntegrationLive.Dadata do
  use DelivestWeb, :live_view

  alias Delivest.Integrations.Dadata
  alias Delivest.Identity
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, Presentation}

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Delivery address on the map"),
       selectable_branches: Identity.list_branch_for_staff(socket.assigns.current_staff)
     )
     |> assign_settings(Dadata.get_settings())
     |> assign_context()}
  end

  @impl true
  def handle_event("validate", %{"dadata" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Dadata.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "dadata"))}
  end

  def handle_event("save", %{"dadata" => params}, socket) do
    case Dadata.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings(settings)
         |> assign_context()
         |> put_flash(:info, gettext("Settings saved"))
         |> push_event("staff:form-saved", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "dadata"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(Dadata.change_settings(settings), as: "dadata")
    )
  end

  defp assign_context(socket) do
    assign(socket, context: Presentation.context(nil))
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      back={~p"/staff/integrations"}
      title={gettext("Delivery address on the map")}
      subtitle={
        gettext(
          "Customers pick the address on the map with dadata.ru suggestions. When it is off, the address is typed into plain fields. The settings are shared by every branch."
        )
      }
    >
      <:actions>
        <button
          type="submit"
          form="dadata-settings"
          class="btn btn-primary"
          phx-disable-with={gettext("Saving...")}
        >{gettext("Save")}</button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.live_component
        module={HealthComponent}
        id="dadata-health"
        provider={:dadata}
        branch_id={nil}
        staff={@current_staff}
        context={@context}
      />

      <.form
        for={@form}
        id="dadata-settings"
        phx-change="validate"
        data-staff-dirty
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:api_key]}
          type="password"
          value={@form[:api_key].value}
          label={gettext("API key")}
        />
        <.input field={@form[:enabled]} type="checkbox" label={gettext("Enabled")} />
        <p class="text-xs text-base-content/60">
          {gettext("Set the delivery city of each branch so suggestions stay inside it.")}
        </p>
        <div class="flex flex-wrap gap-2">
          <.link
            :for={branch <- @selectable_branches}
            navigate={~p"/staff/branches/#{branch.slug}/edit/location"}
            class="link link-primary text-sm"
          >
            {gettext("Delivery city · %{name}", name: branch.name)}
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
