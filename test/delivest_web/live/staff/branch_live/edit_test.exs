defmodule DelivestWeb.Staff.BranchLive.EditTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch
  alias Delivest.Repo

  setup %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id})}
  end

  test "branch settings open on their own page and save", %{conn: conn} do
    branch = insert(:branch, name: "Old name", slug: "old-name")

    {:ok, lv, html} = live(conn, ~p"/staff/branches/old-name/edit")
    assert html =~ "CRM"

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "New name", slug: "new-name"})
             |> render_submit()

    assert Repo.reload!(branch).name == "New name"
  end

  test "a new branch is created from the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/branches/new")

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "Fresh", slug: "fresh"})
             |> render_submit()

    assert Repo.get_by(Branch, slug: "fresh")
  end

  test "taken slug is shown on the form", %{conn: conn} do
    insert(:branch, slug: "taken")
    insert(:branch, slug: "mine")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/mine/edit")

    html = lv |> form("#branch-form", branch_form: %{slug: "taken"}) |> render_submit()
    assert html =~ "has already been taken"
  end

  test "unknown branch goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             live(conn, ~p"/staff/branches/missing/edit")
  end
end
