defmodule DelivestWeb.Staff.BranchLive.TimingTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.{Relations, Repo}
  alias Delivest.Oms.OrderTiming

  test "branch timing and delivery settings edit the same time rules", %{conn: conn} do
    branch = insert(:branch)
    category = insert(:category, name: "Pizza")
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, branch_view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/timing")
    assert has_element?(branch_view, "#branch-timing-form")

    branch_view
    |> form("#branch-timing-form", timing: %{mode: "calculated"})
    |> render_change()

    assert has_element?(branch_view, "table #timing_kitchen_minutes")
    assert has_element?(branch_view, "table #timing-category-#{category.id}")
    refute has_element?(branch_view, "#timing-add-category")
    refute has_element?(branch_view, "#timing_travel_minutes")

    {:ok, delivery_view, _} = live(conn, ~p"/staff/b/#{branch}/delivery/zones")

    delivery_view
    |> form("#delivery-timing-form",
      order_timing: %{mode: "calculated", fixed_delivery_minutes: "60", travel_minutes: "22"}
    )
    |> render_submit()

    branch_view
    |> form("#branch-timing-form",
      timing: %{
        mode: "calculated",
        fixed_delivery_minutes: "45",
        kitchen_minutes: "20",
        packing_minutes: "3",
        category_minutes: %{category.id => "12"}
      }
    )
    |> render_submit()

    assert %{mode: :calculated, kitchen_minutes: 20, packing_minutes: 3, travel_minutes: 22} =
             OrderTiming.get(branch.id)

    assert OrderTiming.get(branch.id).category_minutes == %{category.id => 12}

    assert OrderTiming.fixed_minutes(branch.id) == 45

    assert has_element?(delivery_view, "#delivery-timing-form")

    delivery_view
    |> form("#delivery-timing-form",
      order_timing: %{mode: "fixed", fixed_delivery_minutes: "50", travel_minutes: "22"}
    )
    |> render_submit()

    assert %{mode: :fixed, kitchen_minutes: 20, packing_minutes: 3, travel_minutes: 22} =
             OrderTiming.get(branch.id)

    assert OrderTiming.fixed_minutes(branch.id) == 50

    branch_view
    |> form("#branch-timing-form",
      timing: %{mode: "calculated", category_minutes: %{category.id => ""}}
    )
    |> render_submit()

    assert OrderTiming.get(branch.id).category_minutes == %{}
  end
end
