defmodule Delivest.Oms.Orders.StatusChange do
  import Ecto.Query

  require Logger

  alias Delivest.{Audit, Payments, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity
  alias Delivest.Identity.Staff
  alias Delivest.Oms.{Order, OrderEvents, OrderFlow, OrderLock, OrderTransition}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Payments.Payment
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
        with :ok <- check_online_payment(repo, order, steps),
             {:ok, delivery} <- manual_delivery(repo, order, steps, by, opts),
             opts <- normalize_manual_reason(opts, delivery),
             {:ok, change} <- persist(repo, order, steps, by, opts),
             :ok <- confirm_delivery(repo, delivery, steps) do
          {:ok, change}
        end

      {:ignored, reason} ->
        Logger.info("order #{order.number}: #{OrderFlow.source(by)} #{to} ignored (#{reason})")
        persist(repo, order, [], by, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp manual_delivery(_repo, _order, steps, by, _opts)
       when steps == [] or not is_tuple(by), do: {:ok, nil}

  defp manual_delivery(repo, order, steps, {:staff, staff}, opts) do
    if Enum.any?(steps, fn {_from, to} -> to in [:delivering, :completed] end) and
         order.fulfillment_type == :delivery do
      delivery =
        Delivery
        |> where([d], d.order_id == ^order.id and d.status in [:searching, :assigned, :picked_up])
        |> lock("FOR UPDATE")
        |> repo.one()

      case delivery do
        nil ->
          if Keyword.has_key?(opts, :delivery_id),
            do: {:error, :delivery_changed},
            else: {:ok, nil}

        %Delivery{id: id} = delivery ->
          reason = Keyword.get(opts, :reason)

          cond do
            Keyword.get(opts, :delivery_id) != id ->
              {:error, :delivery_changed}

            Identity.authorize(staff, "orders.update", order.branch_id) != :ok ->
              {:error, :forbidden}

            not is_binary(reason) or String.trim(reason) == "" ->
              {:error, :delivery_reason_required}

            true ->
              {:ok, delivery}
          end
      end
    else
      {:ok, nil}
    end
  end

  defp manual_delivery(_repo, _order, _steps, _by, _opts), do: {:ok, nil}

  defp normalize_manual_reason(opts, nil), do: opts

  defp normalize_manual_reason(opts, _delivery) do
    Keyword.update!(opts, :reason, &(String.trim(&1) |> String.slice(0, 300)))
  end

  defp confirm_delivery(_repo, nil, _steps), do: :ok

  defp confirm_delivery(repo, delivery, steps) do
    {_from, to} = List.last(steps)

    changeset =
      case to do
        :delivering ->
          changeset = Delivery.pick_up_changeset(delivery)

          if delivery.provider == :yandex,
            do:
              Ecto.Changeset.put_change(
                changeset,
                :details,
                Map.put(delivery.details || %{}, "manual_pickup", true)
              ),
            else: changeset

        :completed when delivery.provider == :yandex ->
          Ecto.Changeset.change(delivery,
            details: Map.put(delivery.details || %{}, "manual_delivered", true)
          )

        :completed ->
          Delivery.close_changeset(delivery, :delivered, nil)
      end

    case repo.update(changeset) do
      {:ok, _delivery} -> :ok
      error -> error
    end
  end

  def revert(%Order{} = order, %Staff{} = staff, reason) do
    cond do
      not OrderFlow.can_revert?(staff, order) -> {:error, :forbidden}
      (locked = OrderLock.revert(order)) != :ok -> locked
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
    |> Multi.run(:payments, fn repo, %{order: order, reverted: transition} ->
      if transition.to == :completed,
        do: Payments.reopen(repo, order, {:staff, staff}),
        else: {:ok, []}
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

  defp check_online_payment(repo, %Order{payment_method: :online, channel: nil} = order, steps) do
    if Enum.any?(steps, fn {_from, to} -> to in [:delivering, :completed] end) do
      payments =
        repo.all(
          from(p in Payment,
            where: p.order_id == ^order.id and p.method == :online and p.provider == "yookassa",
            where: p.status == :paid and not is_nil(p.paid_at),
            preload: :refunds
          )
        )

      net =
        Enum.reduce(payments, 0, fn payment, total ->
          refunded =
            payment.refunds
            |> Enum.filter(&(&1.status == :succeeded))
            |> Enum.map(& &1.amount)
            |> Enum.sum()

          total + payment.amount - refunded
        end)

      cond do
        payments == [] -> {:error, :online_payment_not_captured}
        net == order.total_amount -> :ok
        true -> {:error, :online_payment_amount_mismatch}
      end
    else
      :ok
    end
  end

  defp check_online_payment(_repo, _order, _steps), do: :ok

  defp persist(repo, order, steps, by, opts) do
    if Enum.any?(steps, fn {_from, to} -> to == :completed end),
      do: Delivest.Marketing.lock_completion(order.client_id, order.branch_id)

    changeset =
      order
      |> Ecto.Changeset.change()
      |> extra(Keyword.get(opts, :with))
      |> status(steps, Keyword.get(opts, :attrs, %{}))

    reason = Keyword.get(opts, :reason)

    with {:ok, updated} <- repo.update(changeset),
         {:ok, updated} <- Delivest.DeliveryMeasurement.record_handover(repo, updated, steps, by),
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
    report(order, steps, by)
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

  defp report(_order, [], _by), do: :ok

  defp report(order, steps, by) do
    {from, _} = List.first(steps)
    {_, to} = List.last(steps)

    :telemetry.execute(
      [:delivest, :order, :status_changed],
      %{count: 1},
      %{from: from, to: to, source: OrderFlow.source(by), branch_id: order.branch_id}
    )

    :telemetry.execute(
      [:delivest, :order, :stage_duration],
      %{duration: stage_duration(order, from)},
      %{stage: from}
    )

    :ok
  end

  defp stage_duration(order, stage) do
    started_at =
      OrderTransition
      |> where([t], t.order_id == ^order.id and t.to == ^stage and is_nil(t.reverted_at))
      |> order_by([t], desc: t.id)
      |> limit(1)
      |> Repo.one()
      |> case do
        %OrderTransition{inserted_at: at} -> at
        nil -> order.inserted_at
      end

    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end
end
