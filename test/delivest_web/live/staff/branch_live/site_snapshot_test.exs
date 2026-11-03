defmodule DelivestWeb.Staff.BranchLive.SiteSnapshotTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory
  import Phoenix.LiveViewTest

  test "shows the snapshot controls and downloads an archive", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch, slug: "snapshot-branch")
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, view, _html} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/snapshot")
    assert has_element?(view, "#snapshot-export")
    assert has_element?(view, "#snapshot-import-form input[type=file]")

    download = get(conn, ~p"/staff/b/#{branch.slug}/site-snapshot")
    assert response(download, 200) |> String.starts_with?("PK")
  end
end
