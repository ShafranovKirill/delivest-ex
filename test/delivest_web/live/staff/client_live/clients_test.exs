defmodule DelivestWeb.Staff.ClientLive.ClientsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "clients management page" do
    test "renders the clients page and list view for an admin staff member", %{conn: conn} do
      admin_role = insert(:role, permissions: ["admin"])
      staff = insert(:staff, role: admin_role)
      client = insert(:client, name: "Alice Client")

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/clients")

      assert html =~ "Clients"
      assert html =~ "Create Client"
      assert html =~ client.name
    end
  end
end
