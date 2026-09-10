defmodule DelivestWeb.Staff.ClientLive.ClientFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity.Client
  alias Delivest.Identity.Clients

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    current_client_id = socket.assigns[:client] && socket.assigns[:client].id
    new_client_id = assigns.client && assigns.client.id

    if is_nil(socket.assigns[:form]) || current_client_id != new_client_id ||
         socket.assigns[:action] != assigns.action do
      client = assigns.client

      form_data = if client && client.id, do: client, else: %Client{}
      changeset = Client.changeset(form_data, %{})

      status_options =
        Enum.map(Client.statuses(), fn status ->
          {humanize_status(status), Atom.to_string(status)}
        end)

      socket =
        socket
        |> assign(:form, to_form(changeset))
        |> assign(:status_options, status_options)

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"client" => params}, socket) do
    base_form =
      if socket.assigns.client.id,
        do: socket.assigns.client,
        else: %Client{}

    changeset =
      base_form
      |> Client.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"client" => params}, socket) do
    save_client_with_params(socket, socket.assigns.action, params)
  end

  defp save_client_with_params(socket, :edit, params) do
    case Clients.update_client(
           socket.assigns.current_staff,
           socket.assigns.client,
           params
         ) do
      {:ok, client} ->
        notify_parent({:saved, client})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You don't have permission to update clients."))}
    end
  end

  defp save_client_with_params(socket, :new, params) do
    case Clients.create_client(params) do
      {:ok, client} ->
        notify_parent({:saved, client})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp humanize_status(:guest), do: gettext("Guest")
  defp humanize_status(:active), do: gettext("Active")
  defp humanize_status(:blocked), do: gettext("Blocked")
  defp humanize_status(status), do: Atom.to_string(status)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="client-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Client Details")}
          </div>

          <.input
            field={@form[:phone]}
            type="text"
            label={gettext("Phone Number")}
            placeholder="+79991112233"
            required
          />

          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Name")}
            placeholder={gettext("Client Name")}
          />

          <.input
            field={@form[:status]}
            type="select"
            label={gettext("Status")}
            options={@status_options}
            required
          />
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
