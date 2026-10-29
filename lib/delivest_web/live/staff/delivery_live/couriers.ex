defmodule DelivestWeb.Staff.DeliveryLive.Couriers do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, Identity}
  alias Delivest.Identity.Branch.CourierSettings

  on_mount {DelivestWeb.Hooks.Permission, "delivery.read"}

  @impl true
  def mount(_params, _session, socket) do
    settings = Couriers.settings(socket.assigns.current_branch.id) || %CourierSettings{}

    {:ok,
     socket
     |> assign(
       page_title: gettext("Branch couriers"),
       can_edit: Identity.can?(socket.assigns.current_staff, "delivery.update")
     )
     |> assign_form(CourierSettings.changeset(settings, %{}))}
  end

  @impl true
  def handle_event("save", %{"couriers" => params}, socket) do
    case Identity.update_couriers(
           socket.assigns.current_staff,
           socket.assigns.current_branch,
           params
         ) do
      {:ok, _branch} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Settings saved"))
         |> push_navigate(to: ~p"/staff/b/#{socket.assigns.current_branch}/delivery")}

      {:error, :info, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "couriers"))

  defp sources, do: Enum.map(Couriers.providers(), fn {key, name} -> {name, key} end)

  defp searches do
    [
      {gettext("Manually"), :manual},
      {gettext("When cooking starts"), :preparing},
      {gettext("When the order is ready"), :ready}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.page_header
        title={gettext("Branch couriers")}
        subtitle={
          gettext(
            "Who delivers the orders and when the courier search starts. With Frontpad the delivery stays in Frontpad."
          )
        }
        back={~p"/staff/b/#{@current_branch}/delivery"}
      />

      <.form
        for={@form}
        id="couriers-form"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:source]}
            type="select"
            label={gettext("Couriers")}
            options={sources()}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:search]}
            type="select"
            label={gettext("Find a courier")}
            options={searches()}
            disabled={not @can_edit}
          />
        </div>

        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
