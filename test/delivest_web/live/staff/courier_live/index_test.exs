defmodule DelivestWeb.Staff.CourierLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Order.Address
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      address: "Lenina 1",
      latitude: 55.75,
      longitude: 37.61
    })

    courier = staff(["orders.deliver"], branch)

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(
        fulfillment_type: :delivery,
        status: :preparing,
        address: %Address{
          city: "Moscow",
          street: "Tverskaya",
          house: "7",
          entrance: "2",
          floor: "5",
          apartment: "42",
          intercom: "42K",
          latitude: 55.76,
          longitude: 37.6
        }
      )
      |> Repo.update!()

    {:ok, delivery} =
      order.id |> Couriers.Delivery.new(branch.id, :staff) |> Repo.insert()

    %{
      conn: init_test_session(conn, %{"staff_id" => courier.id}),
      branch: branch,
      courier: courier,
      order: order,
      delivery: delivery
    }
  end

  defp staff(permissions, branch) do
    staff = insert(:staff, role: build(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp page(conn, branch), do: live(conn, ~p"/staff/b/#{branch}/deliveries")

  test "the courier takes a request, picks it up when ready and hands it over", ctx do
    {:ok, lv, _html} = page(ctx.conn, ctx.branch)
    assert has_element?(lv, "#courier-open #delivery-#{ctx.delivery.id}")
    assert has_element?(lv, "#courier-mine-empty")
    refute render(lv) =~ "tel:"

    lv |> element("#take-#{ctx.delivery.id}") |> render_click()
    assert has_element?(lv, "#courier-mine #delivery-#{ctx.delivery.id}")
    assert has_element?(lv, "#pick-up-#{ctx.delivery.id}[disabled]")

    card = lv |> element("#delivery-#{ctx.delivery.id}") |> render()
    assert card =~ "Tverskaya"
    assert card =~ "42K"
    assert card =~ "yandexnavi://build_route_on_map?lat_to=55.76&amp;lon_to=37.6"
    assert has_element?(lv, "#delivery-map-#{ctx.delivery.id}[data-from-lat='55.75']")

    ctx.order |> Ecto.Changeset.change(status: :ready) |> Repo.update!()
    Couriers.subscribe(ctx.branch.id)
    send(lv.pid, {:deliveries_changed, ctx.branch.id})

    lv |> element("#pick-up-#{ctx.delivery.id}") |> render_click()
    assert Repo.reload!(ctx.order).status == :delivering

    lv |> element("#hand-over-#{ctx.delivery.id}") |> render_click()
    assert Repo.reload!(ctx.order).status == :completed
    assert has_element?(lv, "#courier-mine-empty")
  end

  test "a request taken by another courier disappears", ctx do
    {:ok, lv, _html} = page(ctx.conn, ctx.branch)
    other = staff(["orders.deliver"], ctx.branch) |> Repo.preload([:role, :branches])

    {:ok, _delivery} = Couriers.take(other, ctx.branch.id, ctx.delivery.id)
    refute has_element?(lv, "#delivery-#{ctx.delivery.id}")
    assert has_element?(lv, "#courier-open-empty")
  end

  test "a courier account lands on the deliveries page", ctx do
    select = ctx.conn |> get(~p"/staff") |> redirected_to()
    assert select == ~p"/staff/branches/select/#{ctx.branch.id}"

    assert ctx.conn |> get(select) |> redirected_to() == ~p"/staff/b/#{ctx.branch}/deliveries"
  end

  test "staff without the delivery permission is turned away", ctx do
    operator = staff(["orders.read"], ctx.branch)
    conn = init_test_session(build_conn(), %{"staff_id" => operator.id})
    assert {:error, {:redirect, _}} = page(conn, ctx.branch)
  end
end
