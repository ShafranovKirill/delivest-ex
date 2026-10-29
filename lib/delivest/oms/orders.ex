defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false

  alias Delivest.Audit
  alias Delivest.Oms.{Order, OrderDeadline, OrderEvents, OrderFlow, OrderScopes, OrderTransition}
  alias Delivest.Oms.Orders.{Create, DraftCart, Filter, Notifier, StatusChange, Update}
  alias Delivest.Repo

  defdelegate subscribe(branch_id), to: Notifier
  defdelegate subscribe_owner(kind, id), to: Notifier
  defdelegate subscribe_branch(branch_id), to: Notifier
  defdelegate create_order(attrs, opts \\ []), to: Create, as: :run
  defdelegate update_order(order, attrs, opts \\ []), to: Update, as: :run
  defdelegate create_draft_cart(order), to: DraftCart, as: :create
  defdelegate populate_cart_from_order(order, cart_id), to: DraftCart, as: :populate
  defdelegate advance_order(order, to, by, opts \\ []), to: StatusChange, as: :run
  defdelegate revert_order_status(order, staff, reason), to: StatusChange, as: :revert
  defdelegate acknowledge_cancel(order, staff), to: StatusChange
  defdelegate courier_changed(order_id), to: Notifier

  def paginate_orders(params, page_params) do
    with {:ok, {orders, meta}} <-
           params
           |> filtered()
           |> sorted(Filter.normalize_params(params))
           |> Flop.validate_and_run(page_params, for: Order) do
      {:ok,
       {Repo.preload(orders, [:items, :client, transitions: [:staff], deliveries: [:courier]]),
        meta}}
    end
  end

  def list_latest_orders(params, limit) do
    params
    |> filtered()
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> preload([:items, :client])
    |> Repo.all()
  end

  defp filtered(params) do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> Filter.apply_filters(Filter.normalize_params(params))
  end

  def count_by_status(params) do
    params
    |> Map.drop([:status, "status"])
    |> filtered()
    |> exclude(:order_by)
    |> group_by([o], o.status)
    |> select([o], {o.status, count()})
    |> Repo.all()
    |> Map.new()
  end

  defp sorted(query, %{"sort" => "time"}), do: query

  defp sorted(query, %{"branch_id" => branch_id}) when is_binary(branch_id),
    do: OrderDeadline.by_urgency(query, OrderDeadline.delivery_minutes(branch_id))

  defp sorted(query, _params), do: query

  def count_client_orders(client_id) do
    Order
    |> where([o], o.client_id == ^client_id and is_nil(o.deleted_at))
    |> where(^OrderScopes.sold())
    |> Repo.aggregate(:count)
  end

  def count_unconfirmed(branch_id) do
    Order
    |> where([o], o.branch_id == ^branch_id and o.status == :created and is_nil(o.deleted_at))
    |> Repo.aggregate(:count)
  end

  def get_client_order(nil, _order_id), do: nil

  def get_client_order(client_id, order_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(order_id) do
      Order
      |> where([o], o.id == ^uuid and o.client_id == ^client_id and is_nil(o.deleted_at))
      |> preload(:items)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def list_client_orders(client_id, branch_scope, limit \\ 50) do
    Order
    |> where([o], o.client_id == ^client_id and is_nil(o.deleted_at))
    |> then(fn query ->
      case branch_scope do
        :all -> query
        ids -> where(query, [o], o.branch_id in ^ids)
      end
    end)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
  end

  def list_active_orders(session_id, client_id \\ nil)
  def list_active_orders(nil, nil), do: []

  def list_active_orders(session_id, client_id) do
    since = DateTime.add(DateTime.utc_now(), -active_hours(), :hour)

    Order
    |> where(^owned_by(session_id, client_id))
    |> where([o], is_nil(o.deleted_at))
    |> where([o], o.inserted_at >= ^since and o.status not in ^OrderFlow.final())
    |> order_by([o], desc: o.inserted_at)
    |> preload([:items, deliveries: :courier])
    |> Repo.all()
  end

  def get_order(id) do
    Order
    |> Repo.get(id)
    |> Repo.preload([:client, :items, transitions: [:staff], deliveries: [:courier]])
  end

  def cancel_order(%Order{} = order, by, attrs) do
    attrs = Filter.normalize_params(attrs)

    advance_order(order, :cancelled, by,
      attrs: Map.take(attrs, ["cancel_reason", "cancel_note"]),
      reason: blank_to_nil(attrs["cancel_note"])
    )
  end

  def update_payment_method(order, attrs, actor \\ :system)

  def update_payment_method(%Order{crm: %{}}, _attrs, actor),
    do: Audit.track({:error, :order_locked}, actor, "order.details_changed")

  def update_payment_method(%Order{} = order, attrs, actor) do
    changeset = Order.payment_changeset(order, Filter.normalize_params(attrs))

    changeset
    |> persist([:order, :updated], fn repo, updated ->
      with {:ok, _payments} <- Delivest.Payments.sync(repo, updated),
           do: OrderEvents.updated(repo, order, updated, actor)
    end)
    |> Audit.track(actor, "order.details_changed", metadata: changeset.changes)
  end

  def acknowledge_branch_cancel(staff, branch_id, order_id) do
    with :ok <- Delivest.Identity.authorize(staff, "orders.update", branch_id),
         {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{} = order <- Repo.get_by(Order, id: uuid, branch_id: branch_id) do
      acknowledge_cancel(order, staff)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :order_not_found}
    end
  end

  def list_unacknowledged_cancellations(branch_id) do
    since = DateTime.add(DateTime.utc_now(), -1, :day)

    Order
    |> where([o], o.branch_id == ^branch_id and o.status == :cancelled and is_nil(o.deleted_at))
    |> where([o], is_nil(o.cancel_acknowledged_at) and o.updated_at >= ^since)
    |> join(:inner, [o], t in OrderTransition,
      on:
        t.order_id == o.id and t.to == :cancelled and t.source == :channel and
          is_nil(t.reverted_at)
    )
    |> distinct(true)
    |> order_by([o], asc: o.updated_at)
    |> Repo.all()
  end

  def update_order_crm(%Order{} = order, attrs) do
    order
    |> Order.crm_changeset(attrs)
    |> persist([:order, :updated])
  end

  def update_order_channel(%Order{} = order, attrs) do
    order
    |> Order.channel_changeset(attrs)
    |> persist([:order, :updated])
  end

  def soft_delete_order(%Order{} = order, actor \\ :system) do
    order
    |> Order.changeset(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
    |> persist([:order, :deleted], &OrderEvents.deleted(&1, &2, actor))
    |> Audit.track(actor, "order.deleted")
  end

  defp owned_by(session_id, nil), do: dynamic([o], o.session_id == ^session_id)
  defp owned_by(nil, client_id), do: dynamic([o], o.client_id == ^client_id)

  defp owned_by(session_id, client_id),
    do: dynamic([o], o.session_id == ^session_id or o.client_id == ^client_id)

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp active_hours, do: Application.get_env(:delivest, :active_order_hours, 7)

  defp persist(changeset, event) do
    changeset
    |> Repo.update()
    |> Notifier.publish(event)
  end

  defp persist(changeset, event, emit) do
    Repo.transaction(fn ->
      with {:ok, order} <- Repo.update(changeset),
           {:ok, _event} <- emit.(Repo, order) do
        order
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> Notifier.publish(event)
  end
end
