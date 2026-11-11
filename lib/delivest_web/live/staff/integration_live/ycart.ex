defmodule DelivestWeb.Staff.IntegrationLive.Ycart do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Identity.Branch.YcartSettings

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    settings = settings(socket.assigns.current_branch)

    {:ok,
     socket
     |> assign(
       page_title: gettext("YCart Settings"),
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       settings: settings
     )
     |> assign_form(YcartSettings.changeset(settings, %{}))}
  end

  @impl true
  def handle_event("validate", %{"ycart" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> YcartSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"ycart" => params}, socket) do
    branch = socket.assigns.current_branch

    case Identity.update_integrations(socket.assigns.current_staff, branch, %{
           "ycart_settings" => params
         }) do
      {:ok, updated} ->
        settings = settings(updated)

        {:noreply,
         socket
         |> assign(settings: settings, current_branch: updated)
         |> assign_form(YcartSettings.changeset(settings, %{}))
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, :info, %Ecto.Changeset{} = changeset} ->
        form_changeset =
          Ecto.Changeset.get_change(changeset, :ycart_settings) ||
            YcartSettings.changeset(socket.assigns.settings, params)

        {:noreply,
         socket
         |> put_flash(:error, gettext("Please check the highlighted fields"))
         |> assign_form(Map.put(form_changeset, :action, :update))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _operation, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  defp settings(branch), do: (branch.info && branch.info.ycart_settings) || %YcartSettings{}

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "ycart"))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.link
        navigate={~p"/staff/b/#{@current_branch}/integrations"}
        class="btn btn-ghost btn-sm -ml-2"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header title={gettext("YCart Settings")} subtitle={@current_branch.name} />

      <.form
        for={@form}
        id="ycart-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("YCart Enabled")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:yandex_org_id]}
          type="text"
          label={gettext("Yandex Org ID")}
          disabled={not @can_edit}
        />
        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>{gettext(
            "Save"
          )}</button>
        </div>
      </.form>
    </div>
    """
  end
end
