defmodule DelivestWeb.Staff.RoleLive.RoleFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity
  alias Delivest.Identity.{Role, Definitions}
  alias Delivest.Features
  alias Delivest.Features.Registry

  import DelivestWeb.Staff.FoundationComponents,
    only: [form_section: 1, error_summary: 1, changeset_errors: 1]

  use Gettext, backend: DelivestWeb.Gettext

  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def update(%{role: role} = assigns, socket) do
    previous_role_id = socket.assigns[:role] && socket.assigns.role.id
    previous_action = socket.assigns[:action]
    changeset = Role.changeset(role, %{})

    disabled_features =
      Registry.permission_features()
      |> Enum.reject(&Features.enabled?(&1, :franchise))

    grouped_permissions =
      Definitions.permissions()
      |> Enum.filter(&Delivest.Identity.grants_permissions?(assigns.current_staff, [&1]))
      |> Enum.reject(&(Registry.permission_feature(&1) in disabled_features))
      |> Enum.group_by(fn perm ->
        parts = String.split(perm, ".")
        if length(parts) == 1, do: "system", else: hd(parts)
      end)

    socket =
      socket
      |> assign(assigns)
      |> assign(:grouped_permissions, grouped_permissions)
      |> assign_new(:save_error, fn -> nil end)

    if is_nil(socket.assigns[:form]) || previous_role_id != role.id ||
         previous_action != assigns.action do
      {:ok, assign(socket, :form, to_form(changeset))}
    else
      {:ok, socket}
    end
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

    {:noreply, assign(socket, form: to_form(changeset), save_error: nil)}
  end

  def handle_event("save", %{"role" => role_params}, socket) do
    role_params = normalize_params(role_params)
    save_role(socket, socket.assigns.action, role_params)
  end

  defp save_role(socket, :edit, role_params) do
    actor = Identity.fresh_staff(socket.assigns.current_staff)

    result =
      if actor,
        do: Identity.update_role(actor, socket.assigns.role, role_params),
        else: {:error, :forbidden}

    case result do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Role updated successfully"))
         |> push_event("staff:form-saved", %{id: "role-form"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           form:
             to_form(
               Role.changeset(socket.assigns.role, role_params)
               |> Map.put(:action, :update)
             )
         )
         |> assign(save_error: gettext("You don't have permission to save this role."))
         |> put_flash(:error, gettext("You don't have permission to save this role."))}
    end
  end

  defp save_role(socket, :new, role_params) do
    actor = Identity.fresh_staff(socket.assigns.current_staff)
    result = if actor, do: Identity.create_role(actor, role_params), else: {:error, :forbidden}

    case result do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Role created successfully"))
         |> push_event("staff:form-saved", %{id: "role-form"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           form: to_form(Role.changeset(%Role{}, role_params) |> Map.put(:action, :insert))
         )
         |> assign(save_error: gettext("You don't have permission to save this role."))
         |> put_flash(:error, gettext("You don't have permission to save this role."))}
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
      <p :if={@save_error} id="role-save-error" role="alert" class="m-4 text-error">{@save_error}</p>
      <.form
        for={@form}
        id="role-form"
        phx-target={@myself}
        phx-change="validate"
        data-staff-dirty
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <.error_summary
            id="role-error-summary"
            errors={changeset_errors(@form.source)}
            form_name={@form.name}
          />
          <.form_section id="role-main-section" title={gettext("Role")}>
            <.input
              field={@form[:name]}
              type="text"
              label={gettext("Role Name")}
              required
              autofocus
            />
          </.form_section>

          <.form_section id="role-permissions-section" title={gettext("Permissions")}>
            <div class="space-y-6">
              <input type="hidden" name="role[permissions][]" value="" />

              <div
                :for={{group, perms} <- @grouped_permissions}
                class="bg-base-200/50 p-4 rounded-box"
              >
                <div class="text-xs font-bold text-base-content/50 uppercase mb-3">
                  {Gettext.dgettext(DelivestWeb.Gettext, "permissions", group)}
                </div>

                <div class="grid grid-cols-1 gap-3">
                  <div
                    :for={perm <- perms}
                    class="flex items-center justify-between p-1 rounded-field"
                  >
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
          </.form_section>
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link navigate={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button
            type="submit"
            class="btn btn-primary"
            data-staff-save={if @action == :new, do: "create", else: "edit"}
            phx-disable-with={gettext("Saving...")}
          >
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
