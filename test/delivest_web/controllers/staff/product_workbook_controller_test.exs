defmodule DelivestWeb.Staff.ProductWorkbookControllerTest do
  use DelivestWeb.ConnCase, async: true
  import Delivest.Factory

  test "downloads a Products workbook without CRM identifiers", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    insert_branch_product(branch.id, name: "Tea", price: 125, external_id: "frontpad-1")

    conn =
      conn
      |> init_test_session(%{"staff_id" => staff.id})
      |> get(~p"/staff/b/#{branch.slug}/products/workbook")

    assert response_content_type(conn, :xlsx) =~ "spreadsheetml.sheet"
    assert {:ok, [%{values: values}]} = Delivest.Net.ProductWorkbook.decode(response(conn, 200))
    assert values["price_rub"] == "1,25"
    refute Map.has_key?(values, "crm_ids")
  end

  test "rejects users without product read access", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn =
      conn
      |> init_test_session(%{"staff_id" => staff.id})
      |> get(~p"/staff/b/#{branch.slug}/products/workbook")

    assert response(conn, 404)
  end
end
