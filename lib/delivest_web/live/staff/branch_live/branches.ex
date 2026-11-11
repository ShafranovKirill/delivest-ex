defmodule DelivestWeb.Staff.BranchLive.Branches do
  use DelivestWeb, :live_view

  alias Delivest.Identity

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "branches.read") or Identity.can?(staff, "delivery.read") do
      branches = Identity.list_branch_for_staff(staff, preload: [:info])

      {:ok,
       assign(socket,
         branches: branches,
         branch_to_delete: nil,
         page_title: gettext("Settings for branches")
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> redirect(to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_event("delete_branch", %{"id" => id}, socket) do
    staff = socket.assigns.current_staff

    branch =
      if Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.delete"),
        do: Enum.find(socket.assigns.branches, &(&1.id == id))

    case branch do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Permission denied"))
         |> assign(branch_to_delete: nil)}

      branch ->
        {:noreply, assign(socket, branch_to_delete: branch)}
    end
  end

  def handle_event("confirm_delete", _, socket) do
    staff = socket.assigns.current_staff
    branch = socket.assigns.branch_to_delete

    if not is_nil(branch) and Identity.can?(staff, "branches.read") and
         Identity.can?(staff, "branches.delete") and
         Enum.any?(socket.assigns.branches, &(&1.id == branch.id)) do
      case Identity.soft_delete_branch(staff, branch) do
        {:ok, deleted_branch} ->
          branches = Enum.reject(socket.assigns.branches, &(&1.id == deleted_branch.id))

          {:noreply,
           socket
           |> put_flash(:info, gettext("Branch deleted successfully"))
           |> assign(branches: branches, branch_to_delete: nil)}

        {:error, :forbidden} ->
          {:noreply, denied_delete(socket)}
      end
    else
      {:noreply, denied_delete(socket)}
    end
  end

  def handle_event("cancel_delete", _, socket),
    do: {:noreply, assign(socket, branch_to_delete: nil)}

  defp denied_delete(socket) do
    socket
    |> put_flash(:error, gettext("You don't have permission to delete branches."))
    |> assign(branch_to_delete: nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="branch-settings-list" class="space-y-6 mx-auto py-4 sm:p-6">
      <.page_header
        title={gettext("Settings for branches")}
        subtitle={gettext("List of available company branches")}
        back={~p"/staff/settings"}
      >
        <:actions>
          <.link
            :if={
              Identity.can?(@current_staff, "branches.read") and
                Identity.can?(@current_staff, "branches.create")
            }
            id="create-branch"
            navigate={~p"/staff/branches/new"}
            class="btn btn-primary"
          >
            {gettext("Create Branch")}
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={branch <- @branches}
          id={"branch-card-#{branch.id}"}
          class="card bg-base-100 border border-base-300"
        >
          <div class="card-body gap-3">
            <h2 class="card-title">{branch.name}</h2>
            <p
              :if={Identity.can?(@current_staff, "branches.read") and branch.is_active == false}
              class="text-xs text-error"
            >
              {gettext("Branch is not active")}
            </p>
            <div class="flex flex-wrap gap-2">
              <.link
                :if={
                  Identity.can?(@current_staff, "branches.read") and
                    Identity.can?(@current_staff, "branches.update")
                }
                id={"branch-edit-#{branch.id}"}
                navigate={~p"/staff/branches/#{branch.slug}/edit"}
                class="btn btn-sm btn-outline"
              >{gettext("Settings")}</.link>
              <.link
                :if={Identity.authorize(@current_staff, "delivery.read", branch.id) == :ok}
                id={"branch-delivery-#{branch.id}"}
                navigate={~p"/staff/b/#{branch}/delivery"}
                class="btn btn-sm btn-outline"
              >{gettext("Delivery")}</.link>
              <button
                :if={
                  Identity.can?(@current_staff, "branches.read") and
                    Identity.can?(@current_staff, "branches.delete")
                }
                id={"branch-delete-#{branch.id}"}
                type="button"
                phx-click="delete_branch"
                phx-value-id={branch.id}
                class="btn btn-sm btn-outline btn-error"
              >{gettext("Delete")}</button>
            </div>
          </div>
        </div>
      </div>

      <.modal
        id="delete-branch-modal"
        show={@branch_to_delete != nil}
        title={gettext("Delete Branch")}
        description={gettext("Are you sure you want to delete this branch?")}
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
