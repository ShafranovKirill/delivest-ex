defmodule DelivestWeb.Staff.DashboardLive.GridTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.Identity.DashboardLayout

  test "a desktop geometry update keeps editing active and a card can then be hidden", %{
    conn: conn
  } do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read", "orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _html} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    assert has_element?(view, "#dashboard-widget-hourly")
    view |> element("#dashboard-edit") |> render_click()

    widgets =
      DashboardLayout.default().widgets
      |> Enum.map(fn item ->
        item
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      end)

    render_hook(view, "dashboard_layout_change", %{"widgets" => widgets})
    assert has_element?(view, "#dashboard-save")
    view |> element("#dashboard-remove-hourly") |> render_click()
    refute has_element?(view, "#dashboard-widget-hourly")
    assert has_element?(view, "#dashboard-add-hourly")
  end
end
