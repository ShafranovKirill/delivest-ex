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

  describe "copying products" do
    setup %{conn: conn} do
      branch = insert(:branch, name: "Source")
      target = insert(:branch, name: "Target")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      %{conn: conn, branch: branch, target: target}
    end

    test "copies the selected products", %{conn: conn, branch: branch, target: target} do
      chosen = insert_branch_product(branch.id, name: "Chosen")
      insert_branch_product(branch.id, name: "Skipped")

      {:ok, lv, _html} = live(conn, ~p"/staff/products")

      lv |> element("#product-selection") |> render_change(%{"ids" => [chosen.id]})
      render_click(lv, "open_copy")

      lv
      |> form("#copy-products-form", %{"target_branch_id" => target.id, "scope" => "selected"})
      |> render_submit()

      assert render(lv) =~ "Products copied: 1"
      assert [_] = Delivest.Relations.list_target_ids("Branch", target.id, "Product")
    end

    test "copies every product of the branch", %{conn: conn, branch: branch, target: target} do
      insert_branch_product(branch.id, name: "One")
      insert_branch_product(branch.id, name: "Two")

      {:ok, lv, _html} = live(conn, ~p"/staff/products")
      render_click(lv, "open_copy")

      lv
      |> form("#copy-products-form", %{"target_branch_id" => target.id, "scope" => "all"})
      |> render_submit()

      assert length(Delivest.Relations.list_target_ids("Branch", target.id, "Product")) == 2
    end
  end
end
