defmodule DelivestWeb.Staff.MenuExportControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
  end

  test "downloads the branch menu as a table", %{conn: conn, branch: branch} do
    insert_branch_product(branch.id,
      name: "Margherita; large",
      price: 49_050,
      external_id: "A-1"
    )

    conn = get(conn, ~p"/staff/b/#{branch.slug}/products/export")

    assert response_content_type(conn, :csv) =~ "text/csv"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "menu-#{branch.slug}.csv"

    body = response(conn, 200)
    assert String.starts_with?(body, <<0xEF, 0xBB, 0xBF>>)
    assert body =~ "\"Margherita; large\";490,50;"
    assert body =~ ";A-1;"
  end

  test "is closed without the products permission", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = conn |> recycle() |> init_test_session(%{"staff_id" => staff.id})

    assert conn |> get(~p"/staff/b/#{branch.slug}/products/export") |> response(404)
  end
end
