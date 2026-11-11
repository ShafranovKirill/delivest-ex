defmodule DelivestWeb.Staff.StaffActiveBranchController do
  use DelivestWeb, :controller

  alias Delivest.{Couriers, Identity}
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Hooks.StaffActiveBranch
  alias DelivestWeb.KitchenAccess
  alias DelivestWeb.StaffBranchPath

  def all(conn, _params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, _staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]) do
      conn
      |> delete_session(:active_branch_id)
      |> redirect(to: ~p"/staff/dashboard")
    else
      _ -> redirect(conn, to: ~p"/staff/auth/login")
    end
  end

  def set(conn, %{"branch_id" => branch_id} = params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         {:ok, branch} <- StaffActiveBranch.accessible(staff, branch_id) do
      case section(params["to"], staff, branch) do
        :unavailable ->
          conn
          |> put_flash(:error, KitchenAccess.message(branch))
          |> redirect(to: ~p"/staff/branches/select")

        section ->
          conn
          |> put_session(:active_branch_id, branch.id)
          |> redirect(to: "/staff/b/#{branch.slug}" <> section)
      end
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("errors", "Branch not found or access denied."))
        |> redirect(to: ~p"/staff/branches/select")
    end
  end

  defp section(to, staff, branch) do
    cond do
      to == "/kitchen" and not Kitchen.available?(staff, branch) -> :unavailable
      StaffBranchPath.valid_section?(to) -> to
      Kitchen.account?(staff) and Kitchen.available?(staff, branch) -> "/kitchen"
      Kitchen.account?(staff) -> :unavailable
      Couriers.account?(staff) -> "/deliveries"
      true -> "/dashboard"
    end
  end
end
