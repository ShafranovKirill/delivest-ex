defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaShared do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, Presentation, YandexEdaAccess}

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Yandex Eda"),
       selectable_branches: Identity.list_branch_for_staff(socket.assigns.current_staff)
     )
     |> assign_shared(YandexEda.get_settings())
     |> assign_context()}
  end

  @impl true
  def handle_event("save_shared", %{"yandex_eda_shared" => params}, socket) do
    case YandexEda.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_shared(settings)
         |> assign_context()
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, shared_form: to_form(changeset, as: "yandex_eda_shared"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  def handle_event("rotate", _params, socket) do
    case YandexEda.rotate_credentials(socket.assigns.current_staff) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_shared(settings)
         |> assign_context()
         |> put_flash(:info, gettext("New access for Yandex Eda is generated"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}
    end
  end

  defp assign_shared(socket, settings),
    do:
      assign(socket,
        shared: settings,
        shared_form: to_form(YandexEda.change_settings(settings), as: "yandex_eda_shared")
      )

  defp assign_context(socket), do: assign(socket, context: Presentation.context(nil))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        back={~p"/staff/integrations"}
        title={gettext("Yandex Eda")}
        subtitle={gettext("Access settings shared by every branch.")}
      />

      <.live_component
        module={HealthComponent}
        id="yandex-eda-health"
        provider={:yandex_eda}
        branch_id={nil}
        staff={@current_staff}
        context={@context}
      />

      <YandexEdaAccess.access settings={@shared} form={@shared_form} />

      <section class="space-y-2">
        <h2 class="font-bold">{gettext("Branch settings")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext("Choose a branch to manage its Yandex Eda settings.")}
        </p>
        <div class="flex flex-wrap gap-2">
          <.link
            :for={branch <- @selectable_branches}
            navigate={~p"/staff/b/#{branch}/integrations/yandex-eda"}
            class="btn btn-sm btn-outline"
          >
            {branch.name}
          </.link>
        </div>
      </section>
    </div>
    """
  end
end
