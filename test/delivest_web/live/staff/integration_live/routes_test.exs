defmodule DelivestWeb.Staff.IntegrationLive.RoutesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Repo

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "routes are toggled per source", %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", webhook_token: "t"}
      }
    })

    {:ok, lv, html} =
      live(
        sign_in(conn, branch, ["integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/routes"
      )

    assert html =~ "Frontpad"

    lv |> element("#route-toggle-staff") |> render_click()
    assert Crm.get_branch_settings(branch.id).sources == ["app"]

    lv |> element("#route-toggle-staff") |> render_click()
    assert Crm.get_branch_settings(branch.id).sources == ["app", "staff"]
  end

  test "without a crm the routes cannot be switched on", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read"]),
        ~p"/staff/b/#{branch}/integrations/routes"
      )

    assert has_element?(lv, "#routes-no-crm")
    assert has_element?(lv, "#route-toggle-app[disabled]")
  end
end
