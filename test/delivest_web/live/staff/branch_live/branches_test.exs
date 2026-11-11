defmodule DelivestWeb.Staff.BranchLive.BranchesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Repo

  test "admin can reach identity and delivery settings", %{conn: conn} do
    branch = insert(:branch, name: "Main Branch")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    assert has_element?(lv, "#branch-settings-list", "Settings for branches")
    assert has_element?(lv, "#create-branch")
    assert has_element?(lv, "#branch-edit-#{branch.id}")
    assert has_element?(lv, "#branch-delivery-#{branch.id}")
    assert has_element?(lv, "#branch-delete-#{branch.id}")
  end

  test "delivery-only staff sees accessible branches and delivery without identity controls", %{
    conn: conn
  } do
    own = insert(:branch, is_active: false)
    foreign = insert(:branch)

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: [
              "delivery.read",
              "branches.delete",
              "branches.create",
              "branches.update"
            ]
          )
      )

    insert(:staff_branch, staff: staff, branch: own)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    assert has_element?(lv, "#branch-card-#{own.id}", own.name)
    refute has_element?(lv, "#branch-card-#{foreign.id}")
    assert has_element?(lv, "#branch-delivery-#{own.id}[href='/staff/b/#{own.slug}/delivery']")
    refute has_element?(lv, "#branch-edit-#{own.id}")
    refute has_element?(lv, "#branch-delete-#{own.id}")
    refute has_element?(lv, "#create-branch")
    refute has_element?(lv, "#branch-card-#{own.id} a[href*='/edit']")
    refute has_element?(lv, "#branch-card-#{own.id}", "Branch is not active")

    lv |> render_hook("delete_branch", %{"id" => own.id})
    lv |> render_hook("confirm_delete", %{})
    assert Repo.reload!(own).deleted_at == nil
  end

  test "delete confirmation without a pending branch is denied", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.delete"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    lv |> render_hook("confirm_delete", %{})
    assert Repo.reload!(branch).deleted_at == nil
  end

  test "delete event cannot target an inaccessible branch", %{conn: conn} do
    own = insert(:branch)
    foreign = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.delete"]))
    insert(:staff_branch, staff: staff, branch: own)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/branches")

    lv |> render_hook("delete_branch", %{"id" => own.id})
    lv |> render_hook("delete_branch", %{"id" => foreign.id})
    lv |> render_hook("confirm_delete", %{})

    assert Repo.reload!(own).deleted_at == nil
    assert Repo.reload!(foreign).deleted_at == nil
  end
end
