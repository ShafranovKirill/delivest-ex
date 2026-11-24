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

  test "reset is a draft that cancel restores and save persists", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read", "orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    custom = %{widgets: [%{id: "revenue", x: 9, y: 4, w: 3, h: 2}], actions: []}
    assert {:ok, ^custom} = DashboardLayout.save(staff.id, custom)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    view |> element("#dashboard-edit") |> render_click()
    view |> element("#dashboard-reset") |> render_click()
    assert has_element?(view, "#dashboard-save")
    assert has_element?(view, "#dashboard-widget-hourly")
    assert DashboardLayout.get(staff.id) == custom

    view |> element("#dashboard-cancel") |> render_click()
    refute has_element?(view, "#dashboard-widget-hourly")
    assert DashboardLayout.get(staff.id) == custom

    view |> element("#dashboard-edit") |> render_click()
    view |> element("#dashboard-reset") |> render_click()
    view |> element("#dashboard-save") |> render_click()
    assert DashboardLayout.get(staff.id) == DashboardLayout.default()
  end

  test "layout updates preserve a widget hidden by permissions", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    hidden = %{id: "attention", x: 5, y: 7, w: 7, h: 2}
    visible = %{id: "revenue", x: 0, y: 0, w: 3, h: 2}
    assert {:ok, _} = DashboardLayout.save(staff.id, %{widgets: [hidden, visible], actions: []})
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/dashboard")
    view |> element("#dashboard-edit") |> render_click()

    widgets = [
      %{"id" => "revenue", "x" => 3, "y" => 0, "w" => 3, "h" => 2},
      %{"id" => "attention", "x" => 5, "y" => 7, "w" => 7, "h" => 2}
    ]

    render_hook(view, "dashboard_layout_change", %{"widgets" => widgets})
    view |> element("#dashboard-save") |> render_click()

    assert DashboardLayout.get(staff.id).widgets == [hidden, %{visible | x: 3}]
  end
end
