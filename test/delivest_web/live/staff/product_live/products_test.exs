defmodule DelivestWeb.Staff.ProductLive.ProductsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "products management page" do
    test "renders the products page and filter controls with a selected branch", %{conn: conn} do
      branch = insert(:branch, name: "North Branch")
      admin_role = insert(:role, permissions: ["admin"])
      staff = insert(:staff, role: admin_role)

      conn =
        init_test_session(conn, %{
          "staff_id" => staff.id,
          "active_branch_id" => branch.id
        })

      {:ok, _lv, html} = live(conn, ~p"/staff/products")

      assert html =~ "Products"
      assert html =~ "Create Product"
      assert html =~ "All categories"
      assert html =~ "All statuses"
    end
  end
end
