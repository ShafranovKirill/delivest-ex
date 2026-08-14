defmodule DelivestWeb.StaffActiveBranchController do
  use DelivestWeb, :controller
  alias Delivest.Net.Branches

  def set(conn, %{"branch_id" => branch_id}) do
    case Branches.get_branch(branch_id) do
      {:ok, _branch} ->
        conn
        |> put_session(:active_branch_id, branch_id)
        |> redirect(to: ~p"/staff/dashboard")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Branch not found")
        |> redirect(to: ~p"/staff/dashboard")
    end
  end
end
