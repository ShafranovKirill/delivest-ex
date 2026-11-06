defmodule DelivestWeb.Staff.IntegrationLive.RkeeperTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm

  test "read-only staff cannot trigger stop sync", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("r_keeper must not be called") end)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/rkeeper")
    render_hook(lv, "sync_stops", %{})
    assert has_element?(lv, "#rkeeper-settings")
  end

  test "the restaurant object and codes are saved", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/rkeeper")
    assert has_element?(lv, "#rkeeper-no-token")

    lv
    |> form("#rkeeper-settings",
      crm: %{rkeeper: %{object_id: "199990377", pickup_type_code: "4", sandbox: "true"}}
    )
    |> render_submit()

    assert %{rkeeper: %{object_id: "199990377", pickup_type_code: "4", sandbox: true}} =
             Crm.get_branch_settings(branch.id)
  end
end
