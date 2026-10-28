defmodule DelivestWeb.Hooks.StaffBranches do
  import Phoenix.Component

  alias Delivest.Identity

  def on_mount(:default, _params, _session, socket),
    do:
      {:cont,
       assign(socket,
         staff_branches: Identity.list_branch_for_staff(socket.assigns.current_staff)
       )}
end
