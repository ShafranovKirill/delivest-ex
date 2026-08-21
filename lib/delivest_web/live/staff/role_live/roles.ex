defmodule DelivestWeb.Staff.RoleLive.Roles do
  use DelivestWeb, :live_view

  alias Delivest.{Identity}
  alias Delivest.Identity.Role

  on_mount {DelivestWeb.Hooks.Permission, "roles.read"}

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    roles =
      staff
      |> Identity.list_all_roles()

    {:ok, assign(socket, roles: roles, role_to_delete: nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "roles.create") do
      assign(socket, page_title: gettext("Create role"), role: %Role{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create role."))
      |> push_patch(to: ~p"/staff/roles")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "roles.update") do
      case Identity.get_role(socket.assigns.current_staff, id) do
        {:ok, role} -> assign(socket, page_title: gettext("Edit role"), role: role)
        _ -> push_patch(socket, to: ~p"/staff/roles")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit role."))
      |> push_patch(to: ~p"/staff/roles")
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Roles"), role: nil)
  end

  @impl true
  def handle_info({DelivestWeb.Staff.RoleLive.RoleFormComponent, {:saved, role}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Role saved successfully"))
     |> push_patch(to: ~p"/staff/roles")
     |> update(:roles, fn roles ->
       if Enum.any?(roles, &(&1.id == role.id)) do
         Enum.map(roles, fn b -> if b.id == role.id, do: role, else: b end)
       else
         [role | roles]
       end
     end)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    if Identity.can?(socket.assigns.current_staff, "roles.delete") do
      {:ok, role} = Identity.get_role(socket.assigns.current_staff, id)
      {:noreply, assign(socket, role_to_delete: role)}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You don't have permission to delete role."))
       |> push_patch(to: ~p"/staff/roles")}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{role_to_delete: role}} = socket) do
    case Identity.delete_role(socket.assigns.current_staff, role) do
      {:ok, deleted_role} ->
        roles = Enum.reject(socket.assigns.roles, &(&1.id == deleted_role.id))

        {:noreply,
         socket
         |> put_flash(:info, gettext("Role deleted successfully"))
         |> assign(roles: roles, role_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete role"))}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, role_to_delete: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6">
      <div class="flex justify-between items-center ">
        <div>
          <h1 class="text-3xl font-bold">{gettext("Roles Management")}</h1>
          <p class="text-sm opacity-70">{gettext("List of available company roles")}</p>
        </div>

        <.link
          :if={Identity.can?(@current_staff, "roles.create")}
          patch={~p"/staff/roles/new"}
          class="btn btn-primary"
        >
          {gettext("Create Role")}
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for role <- @roles do %>
          <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all">
            <div class="card-body flex flex-row items-center justify-between gap-4">
              <.link
                patch={~p"/staff/roles/#{role.id}/edit"}
                class="cursor-pointer flex-1"
              >
                <h2 class="card-title">{role.name}</h2>
              </.link>

              <div class="flex flex-col items-center gap-1 shrink-0">
                <.link
                  :if={Identity.can?(@current_staff, "roles.update")}
                  patch={~p"/staff/roles/#{role.id}/edit"}
                  class="btn btn-sm btn-ghost btn-square text-info"
                  title={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square" class="w-5 h-5" />
                </.link>

                <button
                  :if={Identity.can?(@current_staff, "roles.delete")}
                  type="button"
                  phx-click="delete_click"
                  phx-value-id={role.id}
                  class="btn btn-sm btn-ghost btn-square text-error"
                  title={gettext("Delete")}
                >
                  <.icon name="hero-trash" class="w-5 h-5" />
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <.slide_over
        id="role-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/roles")}
      >
        <.live_component
          :if={@role}
          module={DelivestWeb.Staff.RoleLive.RoleFormComponent}
          id={@role.id || :new}
          action={@live_action}
          role={@role}
          current_staff={@current_staff}
          patch={~p"/staff/roles"}
        />
      </.slide_over>
    </div>
    """
  end
end
