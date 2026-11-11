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
  def render(assigns) do
    ~H"""
    <div id="branch-settings-list" class="space-y-6">
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
                  (Identity.can?(@current_staff, "branches.read") and
                     Identity.can?(@current_staff, "branches.update")) or
                    Identity.authorize(@current_staff, "delivery.read", branch.id) == :ok
                }
                id={"branch-edit-#{branch.id}"}
                navigate={~p"/staff/branches/#{branch.slug}/edit"}
                class="btn btn-sm btn-outline"
              >{gettext("Settings")}</.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
