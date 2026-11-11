defmodule DelivestWeb.Staff.SettingsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "settings hub offers common and only accessible branch settings", %{conn: conn} do
    branch = insert(:branch)
    other = insert(:branch)

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["franchise.update", "branches.read", "branches.update"])
      )

    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/settings")
    assert has_element?(lv, "#settings-common-card")
    assert has_element?(lv, "#settings-branch-card-#{branch.id}")
    refute has_element?(lv, "#settings-branch-card-#{other.id}")
    assert has_element?(lv, "#settings-manage-branches")
  end

  test "franchise-only staff sees common settings without branch settings", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/settings")
    assert has_element?(lv, "#settings-common-card")
    refute has_element?(lv, "[id^='settings-branch-card-']")
    refute has_element?(lv, "#settings-manage-branches")
  end
end
