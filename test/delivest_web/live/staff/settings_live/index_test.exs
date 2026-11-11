defmodule DelivestWeb.Staff.SettingsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  defp login(conn, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    init_test_session(conn, %{"staff_id" => staff.id})
  end

  test "admin hub has three area cards and no individual branch cards", %{conn: conn} do
    insert(:branch)
    {:ok, lv, _} = live(login(conn, ["admin"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-common-card[href='/staff/franchise']")
    assert has_element?(lv, "#settings-branches-card[href='/staff/branches']")
    assert has_element?(lv, "#settings-integrations-card[href='/staff/integrations']")
    refute has_element?(lv, "[id^='settings-branch-card-']")
  end

  test "branches.read alone opens branch settings list", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["branches.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-branches-card")
    refute has_element?(lv, "#settings-common-card")
    refute has_element?(lv, "#settings-integrations-card")
  end

  test "delivery.read alone opens branch settings list", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["delivery.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-branches-card")
    refute has_element?(lv, "#settings-common-card")
    refute has_element?(lv, "#settings-integrations-card")
  end

  test "integrations.read alone opens integrations", %{conn: conn} do
    {:ok, lv, _} = live(login(conn, ["integrations.read"]), ~p"/staff/settings")
    assert has_element?(lv, "#settings-integrations-card")
    refute has_element?(lv, "#settings-common-card")
    refute has_element?(lv, "#settings-branches-card")
  end
end
