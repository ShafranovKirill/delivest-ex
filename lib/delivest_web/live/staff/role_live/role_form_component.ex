defmodule DelivestWeb.Staff.RoleLive.RoleFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity
  alias Delivest.Identity.{Role, Definitions}

  use Gettext, backend: DelivestWeb.Gettext

  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def update(%{role: role} = assigns, socket) do
    changeset = Role.changeset(role, %{})

    grouped_permissions =
      Definitions.permissions()
      |> Enum.group_by(fn perm ->
        parts = String.split(perm, ".")
        if length(parts) == 1, do: "system", else: hd(parts)
      end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))
     |> assign(:grouped_permissions, grouped_permissions)}
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"role" => role_params}, socket) do
    role_params = normalize_params(role_params)

    changeset =
      socket.assigns.role
      |> Role.changeset(role_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"role" => role_params}, socket) do
    role_params = normalize_params(role_params)
    save_role(socket, socket.assigns.action, role_params)
  end

  defp save_role(socket, :edit, role_params) do
    case Identity.update_role(socket.assigns.current_staff, socket.assigns.role, role_params) do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Role updated successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_role(socket, :new, role_params) do
    case Identity.create_role(socket.assigns.current_staff, role_params) do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Role created successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp normalize_params(params) do
    permissions =
      params
      |> Map.get("permissions", [])
      |> case do
        map when is_map(map) -> Map.values(map)
        list when is_list(list) -> list
        _ -> []
      end
      |> List.wrap()
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Map.put(params, "permissions", permissions)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="role-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Role Name")}
            required
            autofocus
          />

          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Permissions")}
          </div>

          <div class="space-y-6">
            <input type="hidden" name="role[permissions][]" value="" />

            <div :for={{group, perms} <- @grouped_permissions} class="bg-base-200/50 p-4 rounded-lg">
              <div class="text-xs font-bold text-base-content/50 uppercase mb-3">
                {Gettext.dgettext(DelivestWeb.Gettext, "permissions", group)}
              </div>

              <div class="grid grid-cols-1 gap-3">
                <div :for={perm <- perms} class="flex items-center justify-between p-1 rounded-md">
                  <label class="label cursor-pointer justify-start gap-3">
                    <input
                      type="checkbox"
                      id={"checkbox-#{perm}"}
                      name="role[permissions][]"
                      value={perm}
                      checked={perm in (@form[:permissions].value || [])}
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="label-text font-bold">
                      {perm_label(perm)}
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp perm_label(perm) do
    action = perm |> String.split(".") |> List.last()
    Gettext.dgettext(DelivestWeb.Gettext, "permissions", action)
  end
end
