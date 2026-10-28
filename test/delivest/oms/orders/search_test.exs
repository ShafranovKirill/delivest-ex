defmodule Delivest.Oms.Orders.SearchTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.Orders

  setup do
    branch = insert(:branch)
    client = insert(:client, name: "Анна Петрова", phone: "+79161234567")

    order = order_fixture(branch.id)
    order = order |> Ecto.Changeset.change(client_id: client.id) |> Repo.update!()
    other = order_fixture(branch.id)

    %{branch: branch, order: order, other: other}
  end

  defp search(branch, term) do
    {:ok, {orders, _meta}} =
      Orders.paginate_orders(%{branch_id: branch.id, search: term, sort: "time"}, %{})

    Enum.map(orders, & &1.id)
  end

  test "finds an order by its number", %{branch: branch, order: order} do
    assert search(branch, "#" <> order.number) == [order.id]
  end

  test "finds an order by the client phone in any format", %{branch: branch, order: order} do
    assert search(branch, "8 (916) 123-45-67") == [order.id]
    assert search(branch, "123-45") == [order.id]
  end

  test "finds an order by the client name", %{branch: branch, order: order} do
    assert search(branch, "петров") == [order.id]
  end

  test "returns every order for a blank term", %{branch: branch, order: order, other: other} do
    assert Enum.sort(search(branch, "  ")) == Enum.sort([order.id, other.id])
  end
end
