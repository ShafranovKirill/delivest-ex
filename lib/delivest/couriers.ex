defmodule Delivest.Couriers do
  import Ecto.Query

  require Logger

  alias Delivest.{Audit, Features, Identity, Push, Repo}
  alias Delivest.Couriers.{Cash, Contact, Delivery, Registry}
  alias Delivest.Identity.{Branch, Staff, StaffBranch}
  alias Delivest.Identity.Branch.{BranchInfo, CourierSettings}
  alias Delivest.Gateway
  alias Delivest.Oms.{Order, OrderFlow, Orders}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Payments.Payment

  @permission "orders.deliver"
  @before_pickup [:accepted, :preparing, :ready]
  @rank %{preparing: 1, ready: 2}
  @handed_over [:picked_up, :delivered]
  @lost_limit 3
  @reporting {__MODULE__, :reporting}

  def permission, do: @permission

  defdelegate balance(branch_id, courier_id), to: Cash
  defdelegate balances(branch_id, courier_ids), to: Cash
  defdelegate empty_balance, to: Cash, as: :empty

  def settle(%Staff{} = staff, branch_id, courier_id) do
    with {:ok, _settlement} = result <- Cash.settle(staff, branch_id, courier_id),
         do: broadcast(result, branch_id)
  end

  def subscribe(branch_id), do: Phoenix.PubSub.subscribe(Delivest.PubSub, topic(branch_id))

  def account?(%Staff{} = staff),
    do: Identity.can?(staff, @permission) and not Identity.can?(staff, "orders.update")

  def account?(_staff), do: false

  def providers, do: Enum.map(Registry.modules(), &{&1.key(), &1.name()})

  def settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, branch} -> branch_settings(branch)
      _error -> nil
    end
  end

  def automatic?(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, branch} -> not Gateway.active?(branch)
      _error -> false
    end
  end

  def own_enabled?(branch_id), do: Features.enabled?("couriers", {:branch, branch_id})

  def active_for_staff?(%Staff{id: courier_id}, branch_id) do
    Repo.exists?(
      where(
        Delivery,
        [d],
        d.branch_id == ^branch_id and d.provider == :staff and d.courier_id == ^courier_id and
          d.status in [:assigned, :picked_up]
      )
    )
  end

  def active_any_in_branch?(branch_id) do
    Repo.exists?(
      where(
        Delivery,
        [d],
        d.branch_id == ^branch_id and d.provider == :staff and
          d.status in [:assigned, :picked_up]
      )
    )
  end

  def unsettled_any_in_branch?(branch_id) do
    Repo.exists?(
      where(
        Payment,
        [p],
        p.branch_id == ^branch_id and p.status == :paid and
          p.method in [:cash, :card] and not is_nil(p.collected_by_id) and
          is_nil(p.settlement_id)
      )
    )
  end

  def unsettled_for_staff?(%Staff{id: courier_id}, branch_id) do
    Repo.exists?(
      where(
        Payment,
        [p],
        p.branch_id == ^branch_id and p.collected_by_id == ^courier_id and
          p.status == :paid and p.method in [:cash, :card] and is_nil(p.settlement_id)
      )
    )
  end

  def eligible?(%Order{fulfillment_type: :delivery, crm: nil} = order),
    do: OrderFlow.active?(order)

  def eligible?(_order), do: false

  def assignable?(%Order{status: status} = order),
    do: status in @before_pickup and eligible?(order)

  def current(%Order{deliveries: deliveries}) when is_list(deliveries),
    do: deliveries |> Enum.filter(&Delivery.active?/1) |> List.last()

  def current(%Order{id: order_id}), do: active(order_id)

  def contact(%Order{deliveries: deliveries} = order) when is_list(deliveries),
    do: order |> current() |> Contact.build()

  def contact(_order), do: nil

  def handed_over?(%Order{deliveries: deliveries}) when is_list(deliveries),
    do: Enum.any?(deliveries, &(&1.status in @handed_over))

  def handed_over?(%Order{id: order_id}),
    do: Repo.exists?(where(Delivery, [d], d.order_id == ^order_id and d.status in ^@handed_over))

  def active(order_id) do
    Delivery
    |> where([d], d.order_id == ^order_id and d.status in ^Delivery.active())
    |> preload(:courier)
    |> Repo.one()
  end

  def list_couriers(branch_id) do
    Staff
    |> join(:inner, [s], sb in StaffBranch,
      on: sb.staff_id == s.id and sb.branch_id == ^branch_id
    )
    |> join(:inner, [s], r in assoc(s, :role))
    |> where([s], is_nil(s.deleted_at))
    |> where([_s, _sb, r], fragment("? @> ?::jsonb", r.permissions, ^[@permission]))
    |> order_by([s], asc: s.name, asc: s.login)
    |> Repo.all()
  end

  def list_open(branch_id) do
    if own_enabled?(branch_id) do
      branch_id
      |> deliveries()
      |> where([d], d.status == :searching and d.provider == :staff)
      |> Repo.all()
    else
      []
    end
  end

  def list_mine(%Staff{id: courier_id}, branch_id) do
    branch_id
    |> deliveries()
    |> where([d], d.courier_id == ^courier_id and d.status in [:assigned, :picked_up])
    |> Repo.all()
  end

  def list_carrying(branch_id) do
    branch_id
    |> deliveries()
    |> where([d], d.provider == :staff and d.status in [:assigned, :picked_up])
    |> Repo.all()
    |> Enum.group_by(& &1.courier_id)
  end

  def order_moved(%Order{} = order, event_id \\ nil) do
    case order.status do
      :cancelled -> close_active(order.id, :cancelled, :order_cancelled)
      :completed -> complete_active(order.id)
      :delivering -> pick_up_active(order.id)
      :ready -> [auto_start(order, event_id), notify_ready(order.id)]
      status when is_map_key(@rank, status) -> auto_start(order, event_id)
      _status -> :ok
    end

    {:ok, order}
  end

  def find(%Staff{} = staff, %Order{} = order) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id),
         true <- assignable?(order) || {:error, :not_available},
         %CourierSettings{source: source} <-
           settings(order.branch_id) || {:error, :not_available},
         nil <- active(order.id) do
      order |> start(source) |> audited(staff, "order.courier_search_started", order)
    else
      %Delivery{} -> {:error, :already_searching}
      error -> error
    end
  end

  def estimate(%Staff{} = staff, %Order{} = order) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id),
         true <- assignable?(order) || {:error, :not_available},
         %CourierSettings{source: :yandex} <-
           settings(order.branch_id) || {:error, :not_available} do
      order |> Repo.preload([:items]) |> Delivest.Integrations.YandexDelivery.estimate()
    else
      %CourierSettings{} -> {:error, :not_available}
      error -> error
    end
  end

  def assign(%Staff{} = staff, %Order{} = order, courier_id) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id),
         true <- assignable?(order) || {:error, :not_available},
         %Staff{} = courier <- branch_courier(order.branch_id, courier_id),
         {:ok, generation} <- own_generation(order.branch_id) do
      order
      |> locked(&reassign(&1, order, courier, staff), generation)
      |> audited(staff, "order.courier_assigned", order, %{courier: courier.name || courier.login})
      |> notified(:delivery_assigned)
    end
  end

  def unassign(%Staff{} = staff, %Order{} = order) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id) do
      action = fn restart?, generation ->
        order
        |> locked(
          fn
            %Delivery{status: :assigned, provider: :staff} = delivery ->
              if restart?,
                do: restart(delivery, :unassigned),
                else: close(delivery, :failed, :unassigned)

            %Delivery{status: :assigned} = delivery ->
              restart(delivery, :unassigned)

            _delivery ->
              {:error, :not_assigned}
          end,
          generation
        )
        |> requested()
        |> audited(staff, "order.courier_unassigned", order)
      end

      case own_generation(order.branch_id) do
        {:ok, generation} ->
          case action.(true, generation) do
            {:error, :disabled} -> action.(false, nil)
            result -> result
          end

        {:error, :disabled} ->
          action.(false, nil)
      end
    end
  end

  def take(%Staff{} = courier, branch_id, delivery_id) do
    with :ok <- Identity.authorize(courier, @permission, branch_id),
         {:ok, generation} <- own_generation(branch_id) do
      transact(
        branch_id,
        delivery_id,
        fn
          %Delivery{status: :searching, provider: :staff} = delivery ->
            delivery |> Delivery.assign_changeset(courier, nil) |> Repo.update()

          _delivery ->
            {:error, :taken}
        end,
        generation
      )
    end
  end

  def refuse(%Staff{} = courier, branch_id, delivery_id) do
    with :ok <- Identity.authorize(courier, @permission, branch_id) do
      action = fn restart?, generation ->
        transact(
          branch_id,
          delivery_id,
          fn delivery ->
            if mine?(delivery, courier, :assigned) do
              if restart?,
                do: restart(delivery, :refused),
                else: close(delivery, :failed, :refused)
            else
              {:error, :not_yours}
            end
          end,
          generation
        )
        |> requested()
      end

      case own_generation(branch_id) do
        {:ok, generation} ->
          case action.(true, generation) do
            {:error, :disabled} -> action.(false, nil)
            result -> result
          end

        {:error, :disabled} ->
          action.(false, nil)
      end
    end
  end

  def pick_up(%Staff{} = courier, branch_id, delivery_id),
    do: move(courier, branch_id, delivery_id, :assigned, :delivering)

  def hand_over(%Staff{} = courier, branch_id, delivery_id),
    do: move(courier, branch_id, delivery_id, :picked_up, :completed)

  def report(%Delivery{id: id, order_id: order_id}, state, details) do
    previous = Repo.get(Delivery, id)
    outer_transaction? = Repo.in_transaction?()

    result = report_transaction(order_id, id, state, details)

    case result do
      {:ok, delivery} = success ->
        if not outer_transaction? && previous &&
             (previous.status != delivery.status ||
                Map.delete(previous.details || %{}, "synced_at") !=
                  Map.delete(delivery.details || %{}, "synced_at")),
           do: broadcast(success, delivery.branch_id)

        success

      error ->
        error
    end
  end

  def publish_report(%Delivery{} = delivery),
    do: broadcast({:ok, delivery}, delivery.branch_id)

  defp report_transaction(order_id, id, state, details) do
    Process.put(@reporting, true)

    order_transaction(fn ->
      if order_id, do: Repo.one(from o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")
      delivery = Repo.one(from d in Delivery, where: d.id == ^id, lock: "FOR UPDATE")
      report_locked(delivery, state, details) |> unwrap()
    end)
  after
    Process.delete(@reporting)
  end

  defp order_transaction(fun),
    do: Notifier.with_commit_notifications(fn -> Repo.transaction(fun) end)

  defp report_locked(delivery, state, details) do
    case delivery do
      %Delivery{} = delivery ->
        if Delivery.active?(delivery) do
          action = fn ->
            if stale_provider_state?(delivery, state, details) do
              {:ok, delivery}
            else
              delivery |> put_details(details) |> reported_safely(state)
            end
          end

          if delivery.provider == :staff and state == :lost do
            case with_own_couriers(delivery.branch_id, action) do
              {:error, :disabled} -> close(delivery, :failed, :not_found)
              result -> result |> changed() |> requested()
            end
          else
            action.()
          end
        else
          {:ok, delivery}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp reported_safely(%Delivery{details: %{"manual_delivered" => true}} = delivery, state) do
    if state == :delivered,
      do: finish(delivery, :delivered, nil),
      else:
        if(state in [:failed, :cancelled, :lost, :returned_finished],
          do: finish(delivery, :failed, :provider_error),
          else: {:ok, delivery}
        )
  end

  defp reported_safely(%Delivery{status: :picked_up} = delivery, state)
       when state in [:lost, :failed, :cancelled, :returned_finished],
       do: finish(delivery, :failed, :provider_error)

  defp reported_safely(delivery, :returned_finished),
    do: finish(delivery, :failed, :provider_error)

  defp reported_safely(delivery, state), do: reported(delivery, state)

  defp stale_provider_state?(%Delivery{provider: :yandex, details: known}, state, incoming) do
    case {known["provider_revision"], incoming["provider_revision"]} do
      {old, new} when is_integer(old) and is_integer(new) and old != new ->
        old > new

      _ ->
        known["status"]
        |> Delivest.Integrations.YandexDelivery.state()
        |> provider_stage()
        |> Kernel.>(provider_stage(state))
    end
  end

  defp stale_provider_state?(_delivery, _state, _details), do: false

  defp provider_stage(:searching), do: 0
  defp provider_stage(:assigned), do: 1
  defp provider_stage(:picked_up), do: 2
  defp provider_stage(:returning), do: 4
  defp provider_stage(:returned_finished), do: 5
  defp provider_stage(_terminal), do: 3

  defp put_details(delivery, details) do
    merged = Map.merge(delivery.details, details)
    delivery |> Delivery.provider_changeset(%{details: merged}) |> Repo.update!()
  end

  defp reported(%Delivery{status: :searching} = delivery, state)
       when state in [:assigned, :picked_up, :delivered] do
    delivery
    |> Delivery.provider_assign_changeset()
    |> Repo.update!()
    |> reported(state)
  end

  defp reported(%Delivery{status: :assigned} = delivery, state)
       when state in [:picked_up, :delivered] do
    with {:ok, _order} <- advance(delivery, :delivering) do
      delivery
      |> Repo.reload!()
      |> then(fn
        %Delivery{status: :assigned} = left ->
          left |> Delivery.pick_up_changeset() |> Repo.update!()

        moved ->
          moved
      end)
      |> reported(state)
    end
  end

  defp reported(%Delivery{status: :picked_up} = delivery, :delivered) do
    with {:ok, %Order{status: :completed}} <- advance(delivery, :completed) do
      delivery |> Repo.reload!() |> Delivery.close_changeset(:delivered, nil) |> Repo.update()
    else
      {:ok, _order} -> {:ok, Repo.reload!(delivery)}
      error -> error
    end
  end

  defp reported(%Delivery{} = delivery, :lost) do
    if lost_count(delivery.order_id) + 1 < @lost_limit,
      do: restart(delivery, :not_found),
      else: close(delivery, :failed, :not_found)
  end

  defp reported(%Delivery{} = delivery, :failed), do: close(delivery, :failed, :provider_error)

  defp reported(%Delivery{} = delivery, :cancelled),
    do: close(delivery, :cancelled, :provider_cancelled)

  defp reported(%Delivery{} = delivery, _state), do: {:ok, delivery}

  defp advance(%Delivery{order_id: order_id}, to) do
    case Repo.get(Order, order_id) do
      nil -> {:error, :order_not_found}
      order -> Orders.advance_order(order, to, :delivery)
    end
  end

  defp lost_count(order_id) do
    Delivery
    |> where([d], d.order_id == ^order_id and d.close_reason == :not_found)
    |> select([d], count(d.id))
    |> Repo.one()
  end

  defp move(courier, branch_id, delivery_id, from, to) do
    with :ok <- Identity.authorize(courier, @permission, branch_id),
         {:ok, delivery} <- fetch(branch_id, delivery_id) do
      order_transaction(fn ->
        order =
          Repo.one(from o in Order, where: o.id == ^delivery.order_id, lock: "FOR UPDATE") ||
            Repo.rollback(:order_not_found)

        current =
          Repo.one(from d in Delivery, where: d.id == ^delivery.id, lock: "FOR UPDATE")

        if not mine?(current, courier, from), do: Repo.rollback(:not_yours)

        case Orders.advance_order(order, to, {:courier, courier}) do
          {:ok, order} ->
            updated =
              case to do
                :delivering -> Delivery.pick_up_changeset(current)
                :completed -> Delivery.close_changeset(current, :delivered, nil)
              end
              |> Repo.update!()

            {order, updated}

          {:error, :skipped_step} ->
            Repo.rollback(:not_ready)

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {order, updated}} ->
          broadcast({:ok, updated}, branch_id)
          order_moved(order)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp reassign(%Delivery{status: :picked_up}, _order, _courier, _staff),
    do: {:error, :picked_up}

  defp reassign(
         %Delivery{status: :assigned, courier_id: id} = delivery,
         _order,
         %{id: id},
         _staff
       ),
       do: {:ok, delivery}

  defp reassign(
         %Delivery{status: :searching, provider: :staff} = delivery,
         _order,
         courier,
         staff
       ),
       do: delivery |> Delivery.assign_changeset(courier, staff) |> Repo.update()

  defp reassign(%Delivery{} = delivery, order, courier, staff) do
    with {:ok, _closed} <- close(delivery, :failed, :reassigned),
         do: reassign(nil, order, courier, staff)
  end

  defp reassign(nil, order, courier, staff) do
    order.id
    |> Delivery.new(order.branch_id, :staff)
    |> Delivery.assign_changeset(courier, staff)
    |> Repo.insert()
  end

  defp restart(%Delivery{provider: :staff} = delivery, reason) do
    with {:ok, _closed} <- close(delivery, :failed, reason) do
      delivery.order_id
      |> Delivery.new(delivery.branch_id, delivery.provider)
      |> Repo.insert()
    end
  end

  defp restart(%Delivery{} = delivery, reason) do
    with {:ok, _closed} <- close(delivery, :failed, reason),
         %Order{} = order <- Repo.get(Order, delivery.order_id) || {:error, :order_not_found} do
      if assignable?(order), do: start(order, delivery.provider), else: {:ok, delivery}
    end
  end

  defp auto_start(%Order{} = order, event_id) do
    with true <- eligible?(order),
         true <- automatic?(order.branch_id),
         %CourierSettings{search: search, source: source} when search != :manual <-
           settings(order.branch_id),
         true <- @rank[order.status] >= @rank[search],
         false <- started?(order.id) do
      start(order, source, event_id)
    end
  end

  defp start(order, key, event_id \\ nil)

  defp start(%Order{} = order, :staff, event_id) do
    event_transaction? = is_binary(event_id) and Repo.in_transaction?()

    with_own_couriers(order.branch_id, fn ->
      changeset = Delivery.new(order.id, order.branch_id, :staff)

      changeset =
        if is_binary(event_id),
          do: Ecto.Changeset.put_change(changeset, :id, event_id),
          else: changeset

      case Repo.insert(changeset) do
        {:error, %Ecto.Changeset{}} -> {:error, :already_searching}
        result -> result
      end
    end)
    |> then(fn result ->
      if event_transaction?, do: result, else: result |> changed() |> requested()
    end)
  end

  defp start(%Order{} = order, key, event_id), do: do_start(order, key, event_id)

  defp do_start(%Order{} = order, key, event_id) do
    changeset = Delivery.new(order.id, order.branch_id, key)

    changeset =
      if is_binary(event_id),
        do: Ecto.Changeset.put_change(changeset, :id, event_id),
        else: changeset

    with {:ok, provider} <- Registry.fetch(key),
         {:ok, delivery} <- Repo.insert(changeset) do
      case provider.start(delivery, order) do
        {:ok, attrs} ->
          delivery
          |> Delivery.provider_changeset(attrs)
          |> Repo.update()
          |> changed()
          |> requested()

        {:error, reason} ->
          Logger.warning(
            "order #{order.number}: #{key} courier search failed (#{inspect(reason)})"
          )

          close(delivery, :failed, :provider_error)
          {:error, reason}
      end
    else
      {:error, %Ecto.Changeset{}} -> {:error, :already_searching}
      error -> error
    end
  end

  defp with_own_couriers(branch_id, fun) do
    scope = {:branch, branch_id}

    with {:ok, generation} <- Features.snapshot("couriers", scope),
         {:ok, result} <- publish_own_courier_work(scope, generation, fun) do
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish_own_courier_work(scope, generation, fun) do
    if Repo.in_transaction?() do
      Features.publish_if_enabled([{"couriers", scope, generation}], fun)
    else
      Features.with_enabled("couriers", scope, generation, fun)
    end
  end

  def publish_started_staff_delivery(event_id) do
    case Repo.get(Delivery, event_id) do
      %Delivery{provider: :staff, status: :searching} = delivery ->
        {:ok, delivery} |> changed() |> requested()
        :ok

      _ ->
        :ok
    end
  end

  defp own_generation(branch_id), do: Features.snapshot("couriers", {:branch, branch_id})

  def give_up(%Delivery{} = delivery) do
    if Delivery.active?(delivery),
      do: report(delivery, :failed, %{}),
      else: {:ok, delivery}
  end

  defp notify_ready(order_id) do
    with %Delivery{provider: key, external_id: external_id} = delivery
         when not is_nil(external_id) <- active(order_id),
         {:ok, provider} <- Registry.fetch(key),
         true <- function_exported?(provider, :order_ready, 1),
         {:error, reason} <- provider.order_ready(delivery) do
      Logger.warning("delivery #{delivery.id}: #{key} order ready failed (#{inspect(reason)})")
    end

    :ok
  end

  defp close_active(order_id, status, reason) do
    case active(order_id) do
      nil -> :ok
      delivery -> close(delivery, status, reason)
    end
  end

  defp complete_active(order_id) do
    case active(order_id) do
      nil -> :ok
      %Delivery{provider: :yandex, details: %{"manual_delivered" => true}} -> :ok
      %Delivery{status: :searching} = delivery -> close(delivery, :cancelled, :order_completed)
      delivery -> close(delivery, :delivered, nil)
    end
  end

  defp pick_up_active(order_id) do
    case active(order_id) do
      %Delivery{status: :assigned} = delivery ->
        delivery |> Delivery.pick_up_changeset() |> Repo.update() |> changed()

      %Delivery{status: :searching} = delivery ->
        close(delivery, :cancelled, :handed_over)

      _delivery ->
        :ok
    end
  end

  defp close(%Delivery{} = delivery, status, reason) do
    case if(status != :delivered, do: cancel_at_provider(delivery), else: :ok) do
      {:paid, price} when reason == :order_cancelled -> hold_cancel(delivery, price)
      _result -> finish(delivery, status, reason)
    end
  end

  defp finish(delivery, status, reason) do
    delivery
    |> Delivery.close_changeset(status, reason)
    |> Repo.update()
    |> changed()
  end

  defp hold_cancel(%Delivery{details: details} = delivery, price) do
    delivery
    |> Ecto.Changeset.change(details: Map.put(details || %{}, "cancel_price", price))
    |> Repo.update()
    |> changed()
  end

  defp cancel_at_provider(%Delivery{provider: key} = delivery) do
    with {:ok, provider} <- Registry.fetch(key),
         {:error, reason} <- provider.cancel(delivery) do
      case reason do
        {:paid_cancel, price} ->
          {:paid, price}

        _other ->
          Logger.warning("delivery #{delivery.id}: #{key} cancel failed (#{inspect(reason)})")
      end
    end
  end

  def cancel_pending(%Order{deliveries: deliveries}) when is_list(deliveries) do
    case Enum.find(deliveries, &(Delivery.active?(&1) and &1.details["cancel_price"])) do
      %Delivery{details: %{"cancel_price" => price}} -> price
      nil -> nil
    end
  end

  def cancel_pending(_order), do: nil

  def confirm_cancel(%Staff{} = staff, %Order{} = order) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id),
         %Delivery{details: %{"cancel_price" => _}, provider: key} = delivery <-
           active(order.id) || {:error, :not_available},
         {:ok, provider} <- Registry.fetch(key),
         :ok <- provider.cancel(delivery) do
      delivery
      |> finish(:cancelled, :order_cancelled)
      |> audited(staff, "order.courier_paid_cancel_confirmed", order)
    else
      %Delivery{} -> {:error, :not_available}
      error -> error
    end
  end

  defp started?(order_id), do: Repo.exists?(where(Delivery, [d], d.order_id == ^order_id))

  defp mine?(%Delivery{courier_id: id, status: status}, %Staff{id: id}, status), do: true
  defp mine?(_delivery, _courier, _status), do: false

  defp branch_courier(branch_id, courier_id) do
    Enum.find(list_couriers(branch_id), &(&1.id == courier_id)) || {:error, :not_a_courier}
  end

  defp deliveries(branch_id) do
    Delivery
    |> join(:inner, [d], o in assoc(d, :order))
    |> where([d, o], d.branch_id == ^branch_id and is_nil(o.deleted_at))
    |> order_by([d], asc: d.inserted_at)
    |> preload([_d, o], order: {o, [:client, items: :modifiers]})
  end

  defp fetch(branch_id, delivery_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(delivery_id),
         %Delivery{} = delivery <- Repo.get_by(Delivery, id: uuid, branch_id: branch_id) do
      {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  defp transact(branch_id, delivery_id, fun, generation) do
    with {:ok, uuid} <- Ecto.UUID.cast(delivery_id) do
      Repo.transaction(fn ->
        with_gate(branch_id, generation, fn ->
          Delivery
          |> where([d], d.id == ^uuid and d.branch_id == ^branch_id)
          |> lock("FOR UPDATE")
          |> Repo.one()
          |> case do
            nil -> Repo.rollback(:not_found)
            delivery -> unwrap(fun.(delivery))
          end
        end)
      end)
      |> broadcast(branch_id)
    else
      :error -> {:error, :not_found}
    end
  end

  defp locked(%Order{} = order, fun, generation) do
    Repo.transaction(fn ->
      with_gate(order.branch_id, generation, fn ->
        Delivery
        |> where([d], d.order_id == ^order.id and d.status in ^Delivery.active())
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> fun.()
        |> unwrap()
      end)
    end)
    |> broadcast(order.branch_id)
  end

  defp with_gate(_branch_id, nil, fun), do: fun.()

  defp with_gate(branch_id, generation, fun) do
    Features.publish_if_enabled([{"couriers", {:branch, branch_id}, generation}], fun)
    |> unwrap()
  end

  defp audited(result, staff, action, order, metadata \\ %{})

  defp audited({:ok, _delivery} = result, staff, action, order, metadata) do
    Audit.record(staff, action, order, metadata: metadata)
    result
  end

  defp audited(error, _staff, _action, _order, _metadata), do: error

  defp requested({:ok, %Delivery{provider: :staff, status: :searching}} = result),
    do: notified(result, :delivery_requested)

  defp requested(result), do: result

  defp notified({:ok, %Delivery{id: id}} = result, event) do
    Push.notify_staff(event, id)
    result
  end

  defp notified(result, _event), do: result

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)

  defp changed({:ok, %Delivery{branch_id: branch_id}} = result), do: broadcast(result, branch_id)
  defp changed(error), do: error

  defp broadcast({:ok, value} = result, branch_id) do
    unless Process.get(@reporting) do
      Phoenix.PubSub.broadcast(
        Delivest.PubSub,
        topic(branch_id),
        {:deliveries_changed, branch_id}
      )

      with %Delivery{order_id: order_id} <- value, do: Orders.courier_changed(order_id)
    end

    result
  end

  defp broadcast(error, _branch_id), do: error

  defp branch_settings(%Branch{info: %BranchInfo{couriers: %CourierSettings{} = settings}}),
    do: settings

  defp branch_settings(_branch), do: %CourierSettings{}

  defp topic(branch_id), do: "couriers:#{branch_id}"
end
