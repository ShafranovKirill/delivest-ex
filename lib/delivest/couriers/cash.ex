defmodule Delivest.Couriers.Cash do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Couriers.Settlement
  alias Delivest.Payments.Payment
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
      insert(staff, branch_id, courier_id)
    end
  end

  defp insert(staff, branch_id, courier_id) do
    Repo.transaction(fn ->
      # Serializes even when no payment rows exist yet. The row locks below fix
      # the exact set used for both the totals and the settlement update.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))", [
        "courier_cash_settlement",
        "#{branch_id}:#{courier_id}"
      ])

      until = DateTime.utc_now()

      payments =
        branch_id
        |> open_payments([courier_id], until)
        |> order_by([p], p.id)
        |> lock("FOR UPDATE")
        |> select([p], %{id: p.id, method: p.method, amount: p.amount, order_id: p.order_id})
        |> Repo.all()

      if payments == [] do
        Repo.rollback(:nothing_to_settle)
      end

      balance = %{
        cash: payments |> Enum.filter(&(&1.method == :cash)) |> Enum.sum_by(& &1.amount),
        card: payments |> Enum.filter(&(&1.method == :card)) |> Enum.sum_by(& &1.amount),
        orders: payments |> Enum.map(& &1.order_id) |> Enum.uniq() |> length()
      }

      case insert_settlement(staff, branch_id, courier_id, balance, until) do
        {:ok, settlement} ->
          ids = Enum.map(payments, & &1.id)

          {updated, _} =
            Payment
            |> where([p], p.id in ^ids and is_nil(p.settlement_id))
            |> Repo.update_all(set: [settlement_id: settlement.id])

          if updated != length(ids), do: Repo.rollback(:settlement_mismatch)
          settlement

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> audited(staff)
  end

  defp insert_settlement(staff, branch_id, courier_id, balance, until) do
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
    branch_id
    |> open_payments(courier_ids, until)
    |> group_by([p], p.collected_by_id)
    |> select([p], {
      p.collected_by_id,
      type(sum(fragment("CASE WHEN ? = 'cash' THEN ? ELSE 0 END", p.method, p.amount)), :integer),
      type(sum(fragment("CASE WHEN ? = 'card' THEN ? ELSE 0 END", p.method, p.amount)), :integer),
      count(p.order_id, :distinct)
    })
  end

  defp open_payments(branch_id, courier_ids, until) do
    Payment
    |> where([p], p.branch_id == ^branch_id and p.collected_by_id in ^courier_ids)
    |> where([p], p.status == :paid and p.method in [:cash, :card] and is_nil(p.settlement_id))
    |> until(until)
  end

  defp until(query, nil), do: query
  defp until(query, at), do: where(query, [p], p.paid_at <= ^at)
end
