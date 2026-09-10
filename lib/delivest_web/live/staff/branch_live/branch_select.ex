defmodule DelivestWeb.Staff.BranchLive.BranchSelect do
  use DelivestWeb, :live_view
  alias Delivest.Identity

  def mount(_params, _session, socket) do
    staff = socket.assigns[:current_staff]

    branches = Identity.list_branch_for_staff(staff)

    {:ok, assign(socket, branches: branches)}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl py-12 px-4 sm:px-6">
      <.header>
        {gettext("Select a branch")}
        <:subtitle>{gettext("Choose a branch to continue working in the system")}</:subtitle>
      </.header>

      <div class="space-y-4">
        <.link
          :for={branch <- @branches}
          href={~p"/staff/branches/select/#{branch.id}"}
          method="get"
          class="block p-6 rounded-2xl border border-base-300 bg-base-100 shadow-sm hover:border-base-content/30 hover:shadow-md transition-all group"
        >
          <h2 class="text-lg font-semibold tracking-tight text-base-content group-hover:text-primary transition-colors">
            {branch.name}
          </h2>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("Click to activate this branch")}
          </p>
        </.link>
      </div>

      <div
        :if={@branches == []}
        class="mt-6 p-6 rounded-2xl border border-base-300 bg-base-100 shadow-sm"
      >
        <p class="text-sm text-base-content/70">
          {gettext(
            "You do not have access to any active branches. Please contact your system administrator."
          )}
        </p>
      </div>
    </div>
    """
  end
end
