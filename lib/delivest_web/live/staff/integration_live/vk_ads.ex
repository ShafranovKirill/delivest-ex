defmodule DelivestWeb.Staff.IntegrationLive.VkAds do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Identity.Branch.VkAdsSettings

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    settings = settings(socket.assigns.current_branch)

    {:ok,
     socket
     |> assign(
       page_title: gettext("VK Реклама / Top.Mail.Ru"),
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       settings: settings
     )
     |> assign_form(VkAdsSettings.changeset(settings, %{}))}
  end

  @impl true
  def handle_event("validate", %{"vk_ads" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> VkAdsSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"vk_ads" => params}, socket) do
    branch = socket.assigns.current_branch

    case Identity.update_integrations(socket.assigns.current_staff, branch, %{
           "vk_ads" => params
         }) do
      {:ok, updated} ->
        settings = settings(updated)

        {:noreply,
         socket
         |> assign(settings: settings, current_branch: updated)
         |> assign_form(VkAdsSettings.changeset(settings, %{}))
         |> put_flash(:info, gettext("Settings saved"))
         |> push_event("staff:form-saved", %{})}

      {:error, :info, %Ecto.Changeset{} = changeset} ->
        form_changeset =
          Ecto.Changeset.get_change(changeset, :vk_ads) ||
            VkAdsSettings.changeset(socket.assigns.settings, params)

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

  defp settings(branch), do: (branch.info && branch.info.vk_ads) || %VkAdsSettings{}

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "vk_ads"))

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("VK Реклама / Top.Mail.Ru")}
      subtitle={@current_branch.name}
      back={~p"/staff/b/#{@current_branch}/integrations"}
    >
      <:actions :if={@can_edit}>
        <button
          type="submit"
          form="vk-ads-settings"
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
      <.form
        for={@form}
        id="vk-ads-settings"
        phx-change="validate"
        data-staff-dirty
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("Включить пиксель на витрине")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:counter_id]}
          type="text"
          label={gettext("ID пикселя")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:privacy_approved]}
          type="checkbox"
          label={gettext("Доступ к счётчику и условия обработки данных подтверждены")}
          disabled={not @can_edit}
        />
        <p class="text-sm text-base-content/60">
          {gettext(
            "Счётчик работает только на публичной витрине выбранного филиала и отправляет просмотры страниц."
          )}
        </p>
      </.form>
    </div>
    """
  end
end
