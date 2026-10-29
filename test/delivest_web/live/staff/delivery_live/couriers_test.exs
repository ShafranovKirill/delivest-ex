defmodule DelivestWeb.Staff.DeliveryLive.CouriersTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Couriers
  alias Delivest.Identity.Branch.CourierSettings

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "branch couriers are chosen in the delivery tab", %{conn: conn} do
    branch = insert(:branch)
    conn = sign_in(conn, branch, ["delivery.read", "delivery.update"])

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/delivery/couriers")

    assert {:error, {:live_redirect, %{to: to}}} =
             lv
             |> form("#couriers-form", couriers: %{source: "yandex", search: "ready"})
             |> render_submit()

    assert to == "/staff/b/#{branch.slug}/delivery"
    assert %CourierSettings{source: :yandex, search: :ready} = Couriers.settings(branch.id)
  end

  test "without delivery editing the couriers only show", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(sign_in(conn, branch, ["delivery.read"]), ~p"/staff/b/#{branch}/delivery/couriers")

    assert has_element?(lv, "#couriers-form select[disabled]")
    refute has_element?(lv, "#couriers-form button[type=submit]")
  end
end
