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
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

    lv
    |> form("#intake-pause-form", %{"duration" => "30", "reason" => "поломка"})
    |> render_submit()

    assert render(lv) =~ "поломка"
    refute Intake.accepting?(branch.id)

    lv |> element("#intake-resume") |> render_click()
    refute has_element?(lv, "#intake-plate")
    assert Intake.accepting?(branch.id)
  end
end
