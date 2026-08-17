defmodule DelivestWeb.Staff.StaffActiveBranchController do
  use DelivestWeb, :controller
  alias Delivest.Identity
  alias Delivest.Net

  def set(conn, %{"branch_id" => branch_id}) do
    staff_id = get_session(conn, :staff_id)

    with staff_id when not is_nil(staff_id) <- staff_id,
         {:ok, current_staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         {:ok, _branch} <- Net.get_branch(branch_id),
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
        |> redirect(to: ~p"/staff/branches/select")
    end
  end
end
