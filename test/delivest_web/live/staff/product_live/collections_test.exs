defmodule DelivestWeb.Staff.ProductLive.CollectionsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "collections offers two separate destinations and one active product entry", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/products/collections")

    assert has_element?(view, "#product-section-tab-collections[aria-current='page']")

    assert has_element?(
             view,
             "#collections-popular a[href='/staff/b/#{branch.slug}/menu/popular']"
           )

    assert has_element?(
             view,
             "#collections-suggested a[href='/staff/b/#{branch.slug}/products/suggested']"
           )

    refute has_element?(view, "#product-section-tab-popular")
    refute has_element?(view, "#product-section-tab-suggested")

    {:ok, suggested, _} = live(conn, ~p"/staff/b/#{branch}/products/suggested")
    assert has_element?(suggested, "#product-section-tab-collections[aria-current='page']")

    assert has_element?(
             suggested,
             "#suggested-toolbar a[href='/staff/b/#{branch.slug}/products/collections'][aria-label='Back']"
           )

    refute has_element?(suggested, "#collections-tab-popular")
    refute has_element?(suggested, "#collections-tab-suggested")
    refute has_element?(suggested, "#suggested-add-products")
  end

  test "collections requires product read permission", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: []))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{branch}/products/collections")
  end
end
