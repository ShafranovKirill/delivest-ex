defmodule Delivest.Oms.Orders.StatusChange do
  import Ecto.Query

  require Logger

  alias Delivest.{Audit, Couriers, Repo}
  alias Delivest.Identity.Staff
  alias Delivest.Oms.{Order, OrderEvents, OrderFlow, OrderTransition}
  alias Delivest.Oms.Orders.Notifier
  alias Ecto.Multi

  def run(%Order{} = order, to, by, opts \\ []) do
    Multi.new()
    |> Multi.run(:locked, fn repo, _ -> lock_order(repo, order.id) end)
    |> Multi.run(:change, fn repo, %{locked: locked} -> apply(repo, locked, to, by, opts) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{change: change}} -> {:ok, finish(change, by, opts)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def apply(repo, %Order{} = order, to, by, opts \\ []) do
    case OrderFlow.steps(order, to, by) do
      {:ok, steps} ->
        persist(repo, order, steps, by, opts)

      {:ignored, reason} ->
        Logger.info("order #{order.number}: #{OrderFlow.source(by)} #{to} ignored (#{reason})")
        persist(repo, order, [], by, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revert(%Order{} = order, %Staff{} = staff, reason) do
    cond do
      not OrderFlow.can_revert?(staff, order) -> {:error, :forbidden}
      Couriers.handed_over?(order) -> {:error, :handed_to_courier}
      true -> do_revert(order, staff, reason)
    end
  end

  defp do_revert(order, staff, reason) do
    Multi.new()
    |> Multi.run(:locked, fn repo, _ -> lock_order(repo, order.id) end)
    |> Multi.run(:transition, fn repo, %{locked: locked} -> last_transition(repo, locked) end)
    |> Multi.update(:reverted, fn %{transition: transition} ->
      OrderTransition.revert_changeset(transition, staff.id, reason)
    end)
    |> Multi.update(:order, fn %{locked: locked, transition: transition} ->
      Order.status_changeset(locked, transition.from)
    end)
    |> Multi.run(:event, fn repo, %{order: order, reverted: transition} ->
      OrderEvents.reverted(repo, order, transition.to, transition.from, staff, reason)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, reverted: transition}} ->
        {:ok, order}
        |> Notifier.publish([:order, :updated])
        |> Audit.track(staff, "order.status_reverted",
          metadata: %{
            from: transition.to,
            to: transition.from,
            reason: transition.revert_reason
          }
        )

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  def acknowledge_cancel(%Order{status: :cancelled} = order, %Staff{} = staff) do
    order
    |> Order.acknowledge_cancel_changeset()
    |> Repo.update()
    |> Notifier.publish([:order, :updated])
    |> Audit.track(staff, "order.cancel_acknowledged")
  end

  def acknowledge_cancel(_order, _staff), do: {:error, :not_cancelled}

  defp lock_order(repo, order_id) do
    query =
      from(o in Order, where: o.id == ^order_id and is_nil(o.deleted_at), lock: "FOR UPDATE")

    case repo.one(query) do
      nil -> {:error, :order_not_found}
      order -> {:ok, order}
    end
  end

  defp persist(repo, order, steps, by, opts) do
    changeset =
      order
      |> Ecto.Changeset.change()
      |> extra(Keyword.get(opts, :with))
      |> status(steps, Keyword.get(opts, :attrs, %{}))

    reason = Keyword.get(opts, :reason)

    with {:ok, updated} <- repo.update(changeset),
         :ok <- record(repo, updated, steps, by, reason),
         {:ok, _payments} <- Delivest.Payments.on_status(repo, updated, steps, by),
         {:ok, _event} <- OrderEvents.status_changed(repo, updated, steps, by, reason) do
      {:ok, %{order: updated, steps: steps, changed?: changeset.changes != %{}}}
    end
  end

  defp extra(changeset, nil), do: changeset
  defp extra(changeset, fun) when is_function(fun, 1), do: fun.(changeset)

  defp status(changeset, [], _attrs), do: changeset

  defp status(changeset, steps, attrs) do
    {_from, to} = List.last(steps)
    Order.status_changeset(changeset, to, attrs)
  end

  defp record(_repo, _order, [], _by, _reason), do: :ok

  defp record(repo, order, steps, by, reason) do
    staff_id = by |> OrderFlow.staff() |> then(&(&1 && &1.id))
    source = OrderFlow.source(by)
    now = DateTime.utc_now()

    rows = Enum.map(steps, &OrderTransition.row(order, &1, source, staff_id, reason, now))
    repo.insert_all(OrderTransition, rows)
    :ok
  end

  defp last_transition(repo, %Order{} = order) do
    query =
      from(t in OrderTransition,
        where: t.order_id == ^order.id and is_nil(t.reverted_at),
        order_by: [desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      %OrderTransition{to: to} = transition when to == order.status -> {:ok, transition}
      _other -> {:error, :nothing_to_revert}
    end
  end

  defp finish(%{order: order, changed?: false}, _by, _opts), do: order

  defp finish(%{order: order, steps: steps}, by, opts) do
    {:ok, order} = Notifier.publish({:ok, order}, [:order, :updated])
    audit(order, steps, by, opts)
    order
  end

  defp audit(_order, [], _by, _opts), do: :ok

  defp audit(order, steps, by, opts) do
    {from, _} = List.first(steps)
    {_, to} = List.last(steps)

    metadata =
      %{from: from, to: to, source: OrderFlow.source(by), reason: Keyword.get(opts, :reason)}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Audit.record(OrderFlow.staff(by) || :system, "order.status_changed", order,
      metadata: metadata
    )
  end
end
