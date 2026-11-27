defmodule DelivestWeb.Staff.BranchLive.Branches do
  use DelivestWeb, :live_view

  alias Delivest.Identity

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Enum.any?(["branches.read", "delivery.read", "orders.update"], &Identity.can?(staff, &1)) do
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

  def staff_page_header(assigns) do
    ~H"""
    <.page_toolbar
      id="branches-toolbar"
      title={gettext("Settings for branches")}
      back={~p"/staff/settings"}
    >
      <:primary_action>
        <.link
          :if={
            Identity.can?(@current_staff, "branches.read") and
              Identity.can?(@current_staff, "branches.create")
          }
          id="create-branch"
          navigate={~p"/staff/branches/new"}
          class="btn btn-primary btn-sm"
        >
          {gettext("Create Branch")}
        </.link>
      </:primary_action>
    </.page_toolbar>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="branch-settings-list" class="space-y-6">
      <.table
        id="branch-settings"
        rows={@branches}
        row_id={&"branch-card-#{&1.id}"}
        show_column_chooser={false}
      >
        <:col :let={branch} label={gettext("Branch")}>
          <span class="font-medium">{branch.name}</span>
          <span
            :if={Identity.can?(@current_staff, "branches.read") and !branch.is_active}
            class="ml-2 badge badge-error badge-soft"
          >{gettext("Branch is not active")}</span>
        </:col>
        <:action :let={branch}>
          <.link
            :if={
              (Identity.can?(@current_staff, "branches.read") and
                 Identity.can?(@current_staff, "branches.update")) or
                Identity.authorize(@current_staff, "delivery.read", branch.id) == :ok or
                Identity.authorize(@current_staff, "orders.update", branch.id) == :ok
            }
            id={"branch-edit-#{branch.id}"}
            navigate={~p"/staff/branches/#{branch.slug}/edit"}
            class="btn btn-sm btn-outline"
          >{gettext("Settings")}</.link>
        </:action>
      </.table>
      <.empty_state :if={@branches == []} title={gettext("No results")} />
    </div>
    """
  end
end
