defmodule DelivestWeb.Staff.RoleLive.RolesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "roles management page" do
    test "renders the roles page and available role cards", %{conn: conn} do
      admin_role = insert(:role, name: "Super Admin", permissions: ["admin"])
      staff = insert(:staff, role: admin_role)
      manager_role = insert(:role, name: "Manager", permissions: ["roles.read"])

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/roles")

      assert html =~ "Roles Management"
      assert html =~ "Create Role"
      assert html =~ "Super Admin"
      assert html =~ manager_role.name
    end
  end
end
