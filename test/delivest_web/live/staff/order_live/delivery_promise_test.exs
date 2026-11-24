defmodule DelivestWeb.Staff.OrderLive.DeliveryPromiseTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{DeliveryMeasurement, LocalTime, Repo}

  test "authorized operator submits promise; forged foreign order and read-only submission fail",
       %{
         conn: conn
       } do
    branch = insert(:branch)
    foreign = insert(:branch)
    order = accepted_delivery(branch.id)
    foreign_order = accepted_delivery(foreign.id)
    operator = staff(branch, ["orders.read", "orders.update"])
    conn = login(conn, branch, operator)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/orders")
    selector = "#delivery-promise-form-#{order.id}"
    assert has_element?(view, selector)

    promised = DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.truncate(:second)
    local = LocalTime.input(promised, branch.id)
    view |> form(selector, promise: %{at: local}) |> render_submit()
    assert Repo.reload!(order).initial_promised_delivery_at == LocalTime.parse(local, branch.id)
    assert length(DeliveryMeasurement.history(order.id)) == 1

    render_hook(view, "confirm_delivery_promise", %{
      "order_id" => foreign_order.id,
      "promise" => %{"at" => local}
    })

    assert is_nil(Repo.reload!(foreign_order).promised_delivery_at)

    reader = staff(branch, ["orders.read"])
    {:ok, read_view, _} = live(login(build_conn(), branch, reader), ~p"/staff/b/#{branch}/orders")
    refute has_element?(read_view, selector)

    render_hook(read_view, "confirm_delivery_promise", %{
      "order_id" => order.id,
      "promise" => %{"at" => LocalTime.input(DateTime.add(promised, 1800), branch.id)}
    })

    assert Repo.reload!(order).promised_delivery_at == LocalTime.parse(local, branch.id)
    assert length(DeliveryMeasurement.history(order.id)) == 1
  end

  defp accepted_delivery(branch_id) do
    branch_id
    |> order_fixture()
    |> Ecto.Changeset.change(status: :accepted, fulfillment_type: :delivery)
    |> Repo.update!()
  end

  defp staff(branch, permissions) do
    person = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: person, branch: branch)
    person
  end

  defp login(conn, branch, person) do
    init_test_session(conn, %{
      "staff_id" => person.id,
      "active_branch_id" => branch.id
    })
  end
end
