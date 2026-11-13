defmodule DelivestWeb.Staff.StaffHomeControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias DelivestWeb.Staff.StaffHomeController

  test "operator starts in orders, manager in overview, courier in deliveries", %{conn: conn} do
    branch = insert(:branch)

    for {permissions, expected} <- [
          {["orders.read", "products.read"], "/orders"},
          {["branches.read", "branches.update", "orders.read"], "/dashboard"},
          {["orders.deliver"], "/deliveries"}
        ] do
      staff = insert(:staff, role: insert(:role, permissions: permissions))
      insert(:staff_branch, staff: staff, branch: branch)

      assert StaffHomeController.branch_home(staff, branch) ==
               "/staff/b/#{branch.slug}" <> expected

      response =
        conn
        |> recycle()
        |> init_test_session(%{"staff_id" => staff.id, "active_branch_id" => branch.id})
        |> get("/staff")

      assert redirected_to(response) == "/staff/b/#{branch.slug}" <> expected

      without_saved_branch =
        conn
        |> recycle()
        |> init_test_session(%{"staff_id" => staff.id})
        |> get("/staff")

      assert redirected_to(without_saved_branch) == "/staff/b/#{branch.slug}" <> expected
    end
  end
end
