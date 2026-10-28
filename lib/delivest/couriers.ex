defmodule Delivest.Couriers do
  import Ecto.Query

  require Logger

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Couriers.{Delivery, Registry}
  alias Delivest.Identity.{Branch, Staff, StaffBranch}
  alias Delivest.Identity.Branch.{BranchInfo, CourierSettings}
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.{Order, OrderFlow, Orders}

  @permission "orders.deliver"
  @before_pickup [:accepted, :preparing, :ready]
  @rank %{preparing: 1, ready: 2}

  def permission, do: @permission

  def subscribe(branch_id), do: Phoenix.PubSub.subscribe(Delivest.PubSub, topic(branch_id))

  def account?(%Staff{} = staff),
    do: Identity.can?(staff, @permission) and not Identity.can?(staff, "orders.update")

  def account?(_staff), do: false

  def providers, do: Enum.map(Registry.modules(), &{&1.key(), &1.name()})

  def settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, branch} -> if Crm.active_provider(branch), do: nil, else: branch_settings(branch)
      _error -> nil
    end
  end

  def eligible?(%Order{fulfillment_type: :delivery, crm: nil} = order),
    do: OrderFlow.active?(order)

  def eligible?(_order), do: false

  def assignable?(%Order{status: status} = order),
    do: status in @before_pickup and eligible?(order)

  def current(%Order{deliveries: deliveries}) when is_list(deliveries),
    do: deliveries |> Enum.filter(&Delivery.active?/1) |> List.last()

  def current(%Order{id: order_id}), do: active(order_id)

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
    branch_id
    |> deliveries()
    |> where([d], d.status == :searching and d.provider == :staff)
    |> Repo.all()
  end

  def list_mine(%Staff{id: courier_id}, branch_id) do
    branch_id
    |> deliveries()
    |> where([d], d.courier_id == ^courier_id and d.status in [:assigned, :picked_up])
    |> Repo.all()
  end

  def order_moved(%Order{} = order) do
    case order.status do
      :cancelled -> close_active(order.id, :cancelled, :order_cancelled)
      :completed -> complete_active(order.id)
      :delivering -> pick_up_active(order.id)
      status when is_map_key(@rank, status) -> auto_start(order)
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

  def assign(%Staff{} = staff, %Order{} = order, courier_id) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id),
         true <- assignable?(order) || {:error, :not_available},
         %Staff{} = courier <- branch_courier(order.branch_id, courier_id) do
      order
      |> locked(&reassign(&1, order, courier, staff))
      |> audited(staff, "order.courier_assigned", order, %{courier: courier.name || courier.login})
    end
  end

  def unassign(%Staff{} = staff, %Order{} = order) do
    with :ok <- Identity.authorize(staff, "orders.update", order.branch_id) do
      order
      |> locked(fn
        %Delivery{status: :assigned} = delivery -> restart(delivery, :unassigned)
        _delivery -> {:error, :not_assigned}
      end)
      |> audited(staff, "order.courier_unassigned", order)
    end
  end

  def take(%Staff{} = courier, branch_id, delivery_id) do
    with :ok <- Identity.authorize(courier, @permission, branch_id) do
      transact(branch_id, delivery_id, fn
        %Delivery{status: :searching, provider: :staff} = delivery ->
          delivery |> Delivery.assign_changeset(courier, nil) |> Repo.update()

        _delivery ->
          {:error, :taken}
      end)
    end
  end

  def refuse(%Staff{} = courier, branch_id, delivery_id) do
    with :ok <- Identity.authorize(courier, @permission, branch_id) do
      transact(branch_id, delivery_id, fn delivery ->
        if mine?(delivery, courier, :assigned),
          do: restart(delivery, :refused),
          else: {:error, :not_yours}
      end)
    end
  end

  def pick_up(%Staff{} = courier, branch_id, delivery_id),
    do: move(courier, branch_id, delivery_id, :assigned, :delivering)

  def hand_over(%Staff{} = courier, branch_id, delivery_id),
    do: move(courier, branch_id, delivery_id, :picked_up, :completed)

  defp move(courier, branch_id, delivery_id, from, to) do
    with :ok <- Identity.authorize(courier, @permission, branch_id),
         {:ok, delivery} <- fetch(branch_id, delivery_id),
         true <- mine?(delivery, courier, from) || {:error, :not_yours},
         %Order{} = order <- Repo.get(Order, delivery.order_id) || {:error, :order_not_found} do
      case Orders.advance_order(order, to, {:courier, courier}) do
        {:ok, order} -> {:ok, order}
        {:error, :skipped_step} -> {:error, :not_ready}
        error -> error
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

  defp restart(%Delivery{} = delivery, reason) do
    with {:ok, _closed} <- close(delivery, :failed, reason) do
      delivery.order_id |> Delivery.new(delivery.branch_id, delivery.provider) |> Repo.insert()
    end
  end

  defp auto_start(%Order{} = order) do
    with true <- eligible?(order),
         %CourierSettings{search: search, source: source} when search != :manual <-
           settings(order.branch_id),
         true <- @rank[order.status] >= @rank[search],
         false <- started?(order.id) do
      start(order, source)
    end
  end

  defp start(%Order{} = order, key) do
    with {:ok, provider} <- Registry.fetch(key),
         {:ok, delivery} <- order.id |> Delivery.new(order.branch_id, key) |> Repo.insert() do
      case provider.start(delivery, order) do
        {:ok, attrs} ->
          delivery |> Delivery.provider_changeset(attrs) |> Repo.update() |> changed()

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

  defp close_active(order_id, status, reason) do
    case active(order_id) do
      nil -> :ok
      delivery -> close(delivery, status, reason)
    end
  end

  defp complete_active(order_id) do
    case active(order_id) do
      nil -> :ok
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
    if status != :delivered, do: cancel_at_provider(delivery)

    delivery
    |> Delivery.close_changeset(status, reason)
    |> Repo.update()
    |> changed()
  end

  defp cancel_at_provider(%Delivery{provider: key} = delivery) do
    with {:ok, provider} <- Registry.fetch(key),
         {:error, reason} <- provider.cancel(delivery) do
      Logger.warning("delivery #{delivery.id}: #{key} cancel failed (#{inspect(reason)})")
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
    |> preload([_d, o], order: {o, [:items, :client]})
  end

  defp fetch(branch_id, delivery_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(delivery_id),
         %Delivery{} = delivery <- Repo.get_by(Delivery, id: uuid, branch_id: branch_id) do
      {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  defp transact(branch_id, delivery_id, fun) do
    with {:ok, uuid} <- Ecto.UUID.cast(delivery_id) do
      Repo.transaction(fn ->
        Delivery
        |> where([d], d.id == ^uuid and d.branch_id == ^branch_id)
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> case do
          nil -> Repo.rollback(:not_found)
          delivery -> unwrap(fun.(delivery))
        end
      end)
      |> broadcast(branch_id)
    else
      :error -> {:error, :not_found}
    end
  end

  defp locked(%Order{} = order, fun) do
    Repo.transaction(fn ->
      Delivery
      |> where([d], d.order_id == ^order.id and d.status in ^Delivery.active())
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> fun.()
      |> unwrap()
    end)
    |> broadcast(order.branch_id)
  end

  defp audited(result, staff, action, order, metadata \\ %{})

  defp audited({:ok, _delivery} = result, staff, action, order, metadata) do
    Audit.record(staff, action, order, metadata: metadata)
    result
  end

  defp audited(error, _staff, _action, _order, _metadata), do: error

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)

  defp changed({:ok, %Delivery{branch_id: branch_id}} = result), do: broadcast(result, branch_id)
  defp changed(error), do: error

  defp broadcast({:ok, _value} = result, branch_id) do
    Phoenix.PubSub.broadcast(Delivest.PubSub, topic(branch_id), {:deliveries_changed, branch_id})
    result
  end

  defp broadcast(error, _branch_id), do: error

  defp branch_settings(%Branch{info: %BranchInfo{couriers: %CourierSettings{} = settings}}),
    do: settings

  defp branch_settings(_branch), do: %CourierSettings{}

  defp topic(branch_id), do: "couriers:#{branch_id}"
end
