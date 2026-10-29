defmodule Delivest.Oms.PickupBoardTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.{OrderTransition, PickupBoard}

  defp order(branch, changes) do
    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  defp ready_at(order, seconds_ago) do
    Repo.insert!(%OrderTransition{
      order_id: order.id,
      from: :preparing,
      to: :ready,
      source: :staff,
      inserted_at: DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    })
  end

  test "pickup and hall orders split into cooking and ready, newest ready first" do
    branch = insert(:branch)
    cooking = order(branch, status: :preparing, fulfillment_type: :dine_in)
    earlier = order(branch, status: :ready)
    later = order(branch, status: :ready)
    ready_at(earlier, 120)
    ready_at(later, 10)

    order(branch, status: :preparing, fulfillment_type: :delivery)
    order(branch, status: :accepted)
    order(branch, status: :completed)
    order(insert(:branch), status: :ready)

    assert %{preparing: [%{id: cooking_id}], ready: [%{id: first}, %{id: second}]} =
             PickupBoard.list(branch.id)

    assert cooking_id == cooking.id
    assert [first, second] == [later.id, earlier.id]
  end
end
