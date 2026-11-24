defmodule DelivestWeb.Staff.BranchLive.TimingTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.Oms.OrderTiming

  test "branch timing and delivery settings edit the same time rules", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, branch_view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/timing")
    assert has_element?(branch_view, "#branch-timing-form")

    branch_view
    |> form("#branch-timing-form", timing: %{mode: "calculated"})
    |> render_change()

    branch_view
    |> form("#branch-timing-form",
      timing: %{
        mode: "calculated",
        fixed_delivery_minutes: "45",
        kitchen_minutes: "20",
        packing_minutes: "3",
        travel_minutes: "18"
      }
    )
    |> render_submit()

    assert %{mode: :calculated, kitchen_minutes: 20, packing_minutes: 3, travel_minutes: 18} =
             OrderTiming.get(branch.id)

    assert OrderTiming.fixed_minutes(branch.id) == 45

    {:ok, delivery_view, _} = live(conn, ~p"/staff/b/#{branch}/delivery/zones")
    assert has_element?(delivery_view, "#delivery-timing-form")

    delivery_view
    |> form("#delivery-timing-form",
      order_timing: %{mode: "fixed", fixed_delivery_minutes: "50", travel_minutes: "22"}
    )
    |> render_submit()

    assert %{mode: :fixed, kitchen_minutes: 20, packing_minutes: 3, travel_minutes: 22} =
             OrderTiming.get(branch.id)

    assert OrderTiming.fixed_minutes(branch.id) == 50
  end
end
