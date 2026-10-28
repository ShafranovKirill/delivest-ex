defmodule DelivestWeb.Staff.StaffActiveBranchController do
  use DelivestWeb, :controller

  alias Delivest.{Couriers, Identity}
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Hooks.StaffActiveBranch
  alias DelivestWeb.StaffBranchPath

  def set(conn, %{"branch_id" => branch_id} = params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         {:ok, branch} <- StaffActiveBranch.accessible(staff, branch_id) do
      conn
      |> put_session(:active_branch_id, branch.id)
      |> redirect(to: "/staff/b/#{branch.slug}" <> section(params["to"], staff))
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("errors", "Branch not found or access denied."))
        |> redirect(to: ~p"/staff/branches/select")
    end
  end

  defp section(to, staff) do
    cond do
      StaffBranchPath.valid_section?(to) -> to
      Kitchen.account?(staff) -> "/kitchen"
      Couriers.account?(staff) -> "/deliveries"
      true -> "/dashboard"
    end
  end
end
