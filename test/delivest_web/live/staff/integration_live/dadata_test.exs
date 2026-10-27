defmodule DelivestWeb.Staff.IntegrationLive.DadataTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Dadata

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    %{conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})}
  end

  test "saves the key and turns the map on", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/integrations")
    assert has_element?(lv, "a#integration-dadata")

    {:ok, lv, _html} = live(conn, ~p"/staff/integrations/dadata")

    lv
    |> form("#dadata-settings", dadata: %{api_key: " key ", enabled: "true"})
    |> render_submit()

    assert %{api_key: "key", enabled: true} = Dadata.get_settings()
    assert Dadata.active?()

    assert %{"data" => %{"address_map" => true}} =
             conn |> get(~p"/client/franchise") |> json_response(200)
  end

  test "is closed without the admin permission", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, _redirect} = live(conn, ~p"/staff/integrations/dadata")
  end
end
