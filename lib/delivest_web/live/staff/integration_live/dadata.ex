defmodule DelivestWeb.Staff.IntegrationLive.Dadata do
  use DelivestWeb, :live_view

  alias Delivest.Integrations.Dadata

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Delivery address on the map"))
     |> assign_settings(Dadata.get_settings())}
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
         socket |> assign_settings(settings) |> put_flash(:info, gettext("Settings saved"))}

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.link navigate={~p"/staff/integrations"} class="btn btn-ghost btn-sm -ml-2">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title={gettext("Delivery address on the map")}
        subtitle={
          gettext(
            "Customers pick the address on the map with dadata.ru suggestions. When it is off, the address is typed into plain fields. The settings are shared by every branch."
          )
        }
      />

      <.form
        for={@form}
        id="dadata-settings"
        phx-change="validate"
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

        <div class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
