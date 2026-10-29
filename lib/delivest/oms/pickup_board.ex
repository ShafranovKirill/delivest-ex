defmodule Delivest.Oms.PickupBoard do
  import Ecto.Query

  alias Delivest.Repo
  alias Delivest.Oms.{Order, OrderTransition}

  @fulfillment_types [:pickup, :dine_in]

  def list(branch_id) do
    orders =
      Order
      |> where([o], o.branch_id == ^branch_id and is_nil(o.deleted_at))
      |> where([o], o.fulfillment_type in ^@fulfillment_types)
      |> where([o], o.status in [:preparing, :ready])
      |> order_by([o], asc: o.inserted_at)
      |> select([o], %{id: o.id, number: o.number, status: o.status, updated_at: o.updated_at})
      |> Repo.all()

    {ready, preparing} = Enum.split_with(orders, &(&1.status == :ready))
    ready_at = ready_at(Enum.map(ready, & &1.id))

    %{
      preparing: preparing,
      ready:
        ready
        |> Enum.map(&Map.put(&1, :ready_at, Map.get(ready_at, &1.id, &1.updated_at)))
        |> Enum.sort_by(& &1.ready_at, {:desc, DateTime})
    }
  end

  defp ready_at([]), do: %{}

  defp ready_at(order_ids) do
    OrderTransition
    |> where([t], t.order_id in ^order_ids and t.to == :ready and is_nil(t.reverted_at))
    |> group_by([t], t.order_id)
    |> select([t], {t.order_id, max(t.inserted_at)})
    |> Repo.all()
    |> Map.new()
  end
end
