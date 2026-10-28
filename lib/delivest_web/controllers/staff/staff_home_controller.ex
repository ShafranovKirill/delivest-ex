defmodule DelivestWeb.Staff.StaffHomeController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Hooks.StaffActiveBranch

  def show(conn, _params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]) do
      redirect(conn, to: home(staff, get_session(conn, :active_branch_id)))
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

  defp branch_home(staff, branch) do
    if Kitchen.account?(staff),
      do: ~p"/staff/b/#{branch}/kitchen",
      else: ~p"/staff/b/#{branch}/dashboard"
  end

  defp only_branch(%{branches: [branch]}), do: ~p"/staff/branches/select/#{branch.id}"
  defp only_branch(_staff), do: ~p"/staff/branches/select"
end
