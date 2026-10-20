defmodule DelivestWeb.Staff.BranchLive.Branches do
  use DelivestWeb, :live_view

  alias Delivest.Identity

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    branches = Identity.list_branch_for_staff(staff, preload: [:info])

    {:ok,
     assign(socket, branches: branches, branch_to_delete: nil, page_title: gettext("Branches"))}
  end

  @impl true
  def handle_event("delete_branch", %{"id" => id}, socket) do
    case Identity.get_branch(id) do
      {:ok, branch} ->
        {:noreply, assign(socket, branch_to_delete: branch)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Branch not found."))}
    end
  end

  @impl true
  def handle_event(
        "confirm_delete",
        _,
        %{assigns: %{branch_to_delete: branch, current_staff: staff} = _assigns} = socket
      ) do
    case Identity.soft_delete_branch(staff, branch) do
      {:ok, deleted_branch} ->
        branches = Enum.reject(socket.assigns.branches, &(&1.id == deleted_branch.id))

        {:noreply,
         socket
         |> put_flash(:info, gettext("Branch deleted successfully"))
         |> assign(branches: branches, branch_to_delete: nil)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You don't have permission to delete branches."))
         |> assign(branch_to_delete: nil)}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, branch_to_delete: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 mx-auto p-6">
      <div class="flex justify-between items-center ">
        <div>
          <h1 class="text-3xl font-bold">{gettext("Branches Management")}</h1>
          <p class="text-sm opacity-70">{gettext("List of available company branches")}</p>
        </div>

        <.link
          :if={Identity.can?(@current_staff, "branches.create")}
          navigate={~p"/staff/branches/new"}
          class="btn btn-primary"
        >
          {gettext("Create Branch")}
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for branch <- @branches do %>
          <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all">
            <div class="card-body flex flex-row items-center justify-between gap-4">
              <.link
                navigate={~p"/staff/branches/#{branch.slug}/edit"}
                class="cursor-pointer flex-1"
              >
                <h2 class="card-title">{branch.name}</h2>
                <p :if={branch.is_active == false} class="text-xs text-error opacity-60 mt-4">
                  {gettext("Branch is not active")}
                </p>
              </.link>

              <div class="flex flex-col items-center gap-1 shrink-0">
                <.link
                  :if={Identity.can?(@current_staff, "branches.update")}
                  navigate={~p"/staff/branches/#{branch.slug}/edit"}
                  class="btn btn-sm btn-ghost btn-square text-info"
                  title={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square" class="w-5 h-5" />
                </.link>

                <button
                  :if={Identity.can?(@current_staff, "branches.delete")}
                  type="button"
                  phx-click="delete_branch"
                  phx-value-id={branch.id}
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
