defmodule DelivestWeb.Staff.IntakeLiveTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Intake

  test "the operator pauses and resumes the intake", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    Delivest.Repo.insert!(%BranchInfo{branch_id: branch.id, delivery_time: 40})
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read", "orders.update"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, orders, _html} = live(conn, ~p"/staff/b/#{branch}/orders")
    {:ok, branches, _html} = live(conn, ~p"/staff/branches")

    assert has_element?(branches, "#branch-edit-#{branch.id}")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    {:ok, second_settings, _html} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    refute has_element?(orders, "#intake-menu")

    assert has_element?(
             lv,
             "#intake-dialog #intake-pause-form[phx-submit*='intake_pause']"
           )

    render_submit(lv, "intake_pause", %{"duration" => "30", "reason" => "поломка"})

    assert render(lv) =~ "поломка"
    refute Intake.accepting?(branch.id)
    assert render(orders) =~ "поломка"
    assert has_element?(second_settings, "#intake-resume")
    refute has_element?(orders, "#intake-resume")

    lv |> element("#intake-resume") |> render_click()
    refute has_element?(lv, "#intake-plate")
    assert Intake.accepting?(branch.id)
    refute has_element?(orders, "#intake-plate")
    refute has_element?(second_settings, "#intake-plate")
  end
end
