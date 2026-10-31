defmodule DelivestWeb.Staff.IntegrationLive.RkeeperTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm

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
