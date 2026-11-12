defmodule DelivestWeb.Staff.DeliveryLive.AddressTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.Delivery

  test "manual address options save and map selection requires DaData", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["delivery.read", "delivery.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _html} = live(conn, ~p"/staff/b/#{branch}/delivery/address")

    view
    |> form("#address-settings", address: %{map_address: "false"})
    |> render_change()

    view
    |> form("#address-settings",
      address: %{map_address: "false", show_city: "true", operator_address: "true"}
    )
    |> render_change()

    view
    |> form("#address-settings", address: %{map_address: "true"})
    |> render_change()

    view
    |> form("#address-settings", address: %{map_address: "false"})
    |> render_change()

    assert has_element?(view, "input[name='address[show_city]'][checked]")
    assert has_element?(view, "input[name='address[operator_address]'][checked]")

    view |> form("#address-settings") |> render_submit()

    assert %{
             map_address: false,
             address_mode_set: true,
             show_city: true,
             operator_address: true
           } = Delivery.get_settings(branch.id)

    view
    |> form("#address-settings", address: %{map_address: "true"})
    |> render_submit()

    assert has_element?(view, "[role=alert]", "Configure DaData before enabling map selection.")
    assert Delivery.get_settings(branch.id).map_address == false
  end
end
