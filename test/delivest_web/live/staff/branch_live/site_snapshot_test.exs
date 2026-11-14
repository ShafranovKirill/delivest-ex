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
    assert has_element?(view, "#snapshot-target", "Import target: #{branch.name}")
    refute has_element?(view, "#snapshot-import-confirm")

    upload =
      file_input(view, "#snapshot-import-form", :snapshot, [
        %{name: "snapshot.zip", content: "invalid archive", type: "application/zip"}
      ])

    assert render_upload(upload, "snapshot.zip") =~ "snapshot.zip"
    assert has_element?(view, "#snapshot-import-confirm[data-confirm]")

    download = get(conn, ~p"/staff/b/#{branch.slug}/site-snapshot")
    assert response(download, 200) |> String.starts_with?("PK")
  end

  test "download enforces branch access and franchise permissions", %{conn: conn} do
    allowed = insert(:branch)
    forbidden = insert(:branch)
    read_permissions = ~w(branches.read categories.read products.read delivery.read)

    staff =
      insert(:staff, role: insert(:role, permissions: ["franchise.update" | read_permissions]))

    insert(:staff_branch, staff: staff, branch: allowed)
    signed_in = init_test_session(conn, %{"staff_id" => staff.id})

    assert signed_in |> get(~p"/staff/b/#{allowed.slug}/site-snapshot") |> response(200)
    assert signed_in |> get(~p"/staff/b/#{forbidden.slug}/site-snapshot") |> response(404)

    reader = insert(:staff, role: insert(:role, permissions: read_permissions))
    insert(:staff_branch, staff: reader, branch: allowed)
    read_only = init_test_session(conn, %{"staff_id" => reader.id})
    assert read_only |> get(~p"/staff/b/#{allowed.slug}/site-snapshot") |> response(404)
  end
end
