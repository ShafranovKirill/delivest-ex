defmodule DelivestWeb.Staff.DeliveryLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "delivery opens zones and couriers from cards", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["delivery.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/delivery")

    assert has_element?(
             lv,
             ~s(#delivery-zones-card[href="/staff/b/#{branch.slug}/delivery/zones"])
           )

    assert has_element?(
             lv,
             ~s(#delivery-couriers-card[href="/staff/b/#{branch.slug}/delivery/couriers"])
           )

    refute has_element?(lv, "#delivery-settings")
  end
end
