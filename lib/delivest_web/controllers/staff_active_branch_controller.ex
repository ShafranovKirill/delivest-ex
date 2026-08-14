defmodule DelivestWeb.Staff.StaffActiveBranchController do
  use DelivestWeb, :controller
  alias Delivest.Identity
  alias Delivest.Net.Branches

  def set(conn, %{"branch_id" => branch_id}) do
    current_staff = conn.assigns[:current_staff]

    with {:ok, _branch} <- Branches.get_branch(branch_id),
         true <- Identity.has_branch_access?(current_staff, branch_id) do
      conn
      |> put_session(:active_branch_id, branch_id)
      |> redirect(to: ~p"/staff/dashboard")
    else
      _ ->
        conn
        |> put_flash(
          :error,
          Gettext.dgettext(
            DelivestWeb.Gettext,
            "error",
            "Branch not found or access denied."
          )
        )
        |> redirect(to: "/staff/branches/select")
    end
  end
end
