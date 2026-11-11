defmodule DelivestWeb.Staff.IntegrationLive.YcartTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)

    editor =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: editor, branch: branch)

    %{conn: init_test_session(conn, %{"staff_id" => editor.id}), branch: branch}
  end

  test "integration editor saves YCart in branch info", %{conn: conn, branch: branch} do
    {:ok, index, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(index, "a#integration-ycart")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/ycart")

    lv
    |> form("#ycart-settings", ycart: %{enabled: "true", yandex_org_id: "12345"})
    |> render_submit()

    assert %{enabled: true, yandex_org_id: "12345"} =
             Repo.get_by!(BranchInfo, branch_id: branch.id).ycart_settings
  end

  test "read-only staff cannot save", %{conn: conn, branch: branch} do
    reader = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: reader, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => reader.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/ycart")
    refute has_element?(lv, "#ycart-settings button[type='submit']")

    lv |> element("#ycart-settings") |> render_submit(%{"ycart" => %{"enabled" => "true"}})

    assert is_nil(Repo.get_by(BranchInfo, branch_id: branch.id))
  end

  test "inaccessible branch cannot be opened", %{conn: conn} do
    foreign = insert(:branch)

    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/b/#{foreign}/integrations/ycart")
  end

  test "enabled map without an organization ID is shown as enabled, not connection health", %{
    conn: conn,
    branch: branch
  } do
    {:ok, editor, _} = live(conn, ~p"/staff/b/#{branch}/integrations/ycart")

    editor
    |> form("#ycart-settings", ycart: %{enabled: "true", yandex_org_id: ""})
    |> render_submit()

    assert %{enabled: true, yandex_org_id: nil} =
             Repo.get_by!(BranchInfo, branch_id: branch.id).ycart_settings

    {:ok, index, _} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(index, "#integration-ycart-state", "Enabled")
    refute has_element?(index, "#integration-ycart-state", "OK")
  end
end
