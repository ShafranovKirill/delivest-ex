defmodule Delivest.Couriers.Cash do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Couriers.{Delivery, Settlement}
  alias Delivest.Identity.Staff

  @empty %{cash: 0, card: 0, orders: 0}

  def empty, do: @empty

  def balance(branch_id, courier_id),
    do: branch_id |> balances([courier_id]) |> Map.get(courier_id, @empty)

  def balances(branch_id, courier_ids, until \\ nil) do
    branch_id
    |> collected(courier_ids, until)
    |> Repo.all()
    |> Map.new(fn {courier_id, cash, card, orders} ->
      {courier_id, %{cash: cash || 0, card: card || 0, orders: orders}}
    end)
  end

  def settle(%Staff{} = staff, branch_id, courier_id) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      until = DateTime.utc_now()

      case balances(branch_id, [courier_id], until) do
        %{^courier_id => balance} -> insert(staff, branch_id, courier_id, balance, until)
        _empty -> {:error, :nothing_to_settle}
      end
    end
  end

  defp insert(staff, branch_id, courier_id, balance, until) do
    %Settlement{
      branch_id: branch_id,
      courier_id: courier_id,
      accepted_by_id: staff.id,
      cash_amount: balance.cash,
      card_amount: balance.card,
      orders_count: balance.orders,
      until: until
    }
    |> Repo.insert()
    |> audited(staff)
  end

  defp audited({:ok, settlement} = result, staff) do
    Audit.record(staff, "courier.cash_settled", Repo.get(Staff, settlement.courier_id),
      metadata: %{
        branch_id: settlement.branch_id,
        cash: settlement.cash_amount,
        card: settlement.card_amount,
        orders: settlement.orders_count
      }
    )

    result
  end

  defp audited(error, _staff), do: error

  defp collected(branch_id, courier_ids, until) do
    last =
      from(s in Settlement,
        where: s.branch_id == ^branch_id,
        group_by: s.courier_id,
        select: %{courier_id: s.courier_id, until: max(s.until)}
      )

    Delivery
    |> join(:inner, [d], o in assoc(d, :order))
    |> join(:left, [d], s in subquery(last), on: s.courier_id == d.courier_id)
    |> where([d], d.branch_id == ^branch_id and d.courier_id in ^courier_ids)
    |> where([d], d.provider == :staff and d.status == :delivered)
    |> where([d, _o, s], is_nil(s.until) or d.closed_at > s.until)
    |> where([_d, o], o.payment_method in [:cash, :card_offline])
    |> until(until)
    |> group_by([d], d.courier_id)
    |> select([d, o], {
      d.courier_id,
      sum(fragment("CASE WHEN ? = 'cash' THEN ? ELSE 0 END", o.payment_method, o.total_amount)),
      sum(
        fragment(
          "CASE WHEN ? = 'card_offline' THEN ? ELSE 0 END",
          o.payment_method,
          o.total_amount
        )
      ),
      count(d.id)
    })
  end

  defp until(query, nil), do: query
  defp until(query, at), do: where(query, [d], d.closed_at <= ^at)
end
