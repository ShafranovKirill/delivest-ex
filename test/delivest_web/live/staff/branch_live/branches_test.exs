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
    refute has_element?(lv, "#branch-delivery-#{branch.id}")
    refute has_element?(lv, "#branch-delete-#{branch.id}")
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
    assert has_element?(lv, "#branch-edit-#{own.id}[href='/staff/branches/#{own.slug}/edit']")
    refute has_element?(lv, "#branch-delivery-#{own.id}")
    refute has_element?(lv, "#branch-delete-#{own.id}")
    refute has_element?(lv, "#create-branch")
    refute has_element?(lv, "#branch-card-#{own.id}", "Branch is not active")

    {:ok, overview, _} = live(conn, ~p"/staff/branches/#{own.slug}/edit")
    assert has_element?(overview, "#branch-delivery-card")
    refute has_element?(overview, "#branch-section-general")
    refute has_element?(overview, "#branch-delete-section")
    refute has_element?(overview, "[href='/staff/branches/#{own.slug}/edit/general']")

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             live(conn, ~p"/staff/branches/#{own.slug}/edit/general")

    overview |> render_hook("reset_board_token", %{})
    overview |> render_hook("confirm_delete", %{"confirmation" => %{"name" => own.name}})
    assert Repo.reload!(own).deleted_at == nil
  end

  test "branch list has no delete action even for branch deletion staff", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.delete"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/branches")
    refute has_element?(lv, "#branch-delete-#{branch.id}")
    refute has_element?(lv, "#delete-branch-modal")
    assert Repo.reload!(branch).deleted_at == nil
  end

  test "branch list shows no delete action for inaccessible branches", %{conn: conn} do
    own = insert(:branch)
    foreign = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.delete"]))
    insert(:staff_branch, staff: staff, branch: own)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/branches")

    assert has_element?(lv, "#branch-card-#{own.id}")
    refute has_element?(lv, "#branch-card-#{foreign.id}")
    refute has_element?(lv, "#branch-delete-#{own.id}")
    assert Repo.reload!(own).deleted_at == nil
    assert Repo.reload!(foreign).deleted_at == nil
  end
end
