defmodule DelivestWeb.Staff.StaffHomeController do
  use DelivestWeb, :controller

  alias Delivest.{Couriers, Identity}
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Hooks.StaffActiveBranch
  alias DelivestWeb.KitchenAccess

  def show(conn, _params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]) do
      branch_id = get_session(conn, :active_branch_id)
      path = home(staff, branch_id)

      conn =
        if Kitchen.account?(staff) and path == "/staff/branches/select" and is_binary(branch_id),
          do: put_flash(conn, :error, KitchenAccess.message(branch_id)),
          else: conn

      redirect(conn, to: path)
    else
      _ -> redirect(conn, to: ~p"/staff/auth/login")
    end
  end

  defp home(staff, branch_id) do
    case StaffActiveBranch.accessible(staff, branch_id) do
      {:ok, branch} -> branch_home(staff, branch)
      :error -> only_branch(staff)
    end
  end

  def branch_home(staff, branch) do
    cond do
      Kitchen.account?(staff) and Kitchen.available?(staff, branch) ->
        ~p"/staff/b/#{branch}/kitchen"

      Kitchen.account?(staff) ->
        "/staff/branches/select"

      Couriers.account?(staff) ->
        ~p"/staff/b/#{branch}/deliveries"

      Identity.can?(staff, "branches.update") ->
        ~p"/staff/b/#{branch}/dashboard"

      Identity.can?(staff, "orders.read") ->
        ~p"/staff/b/#{branch}/orders"

      Identity.can?(staff, "products.read") ->
        ~p"/staff/b/#{branch}/products"

      true ->
        "/staff/branches/select"
    end
  end

  defp only_branch(staff) do
    case staff.branches do
      [branch] ->
        case StaffActiveBranch.accessible(staff, branch.id) do
          {:ok, accessible_branch} -> branch_home(staff, accessible_branch)
          :error -> "/staff/branches/select"
        end

      _ ->
        if Kitchen.account?(staff) or Couriers.account?(staff),
          do: ~p"/staff/branches/select",
          else: ~p"/staff/dashboard"
    end
  end
end
