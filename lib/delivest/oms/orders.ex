defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false

  alias Delivest.Audit
  alias Delivest.Oms.{Order, OrderDeadline, OrderScopes, OrderStatus}
  alias Delivest.Oms.Orders.{Create, DraftCart, Filter, Notifier, Update}
  alias Delivest.Repo

  defdelegate subscribe(branch_id), to: Notifier
  defdelegate subscribe_owner(kind, id), to: Notifier
  defdelegate subscribe_branch(branch_id), to: Notifier
  defdelegate create_order(attrs, opts \\ []), to: Create, as: :run
  defdelegate update_order(order, attrs, opts \\ []), to: Update, as: :run
  defdelegate create_draft_cart(order), to: DraftCart, as: :create
  defdelegate populate_cart_from_order(order, cart_id), to: DraftCart, as: :populate

  def paginate_orders(params, page_params) do
    with {:ok, {orders, meta}} <-
           params
           |> filtered()
           |> sorted(Filter.normalize_params(params))
           |> Flop.validate_and_run(page_params, for: Order) do
      {:ok, {Repo.preload(orders, [:items, :client]), meta}}
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
    statuses =
      params
      |> Map.drop([:status, "status"])
      |> filtered()
      |> select(^%{status: OrderScopes.effective_status()})

    from(s in subquery(statuses), group_by: s.status, select: {s.status, count()})
    |> Repo.all()
    |> Map.new(fn {status, count} -> {String.to_existing_atom(status), count} end)
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
    |> where([o], o.inserted_at >= ^since and o.status not in ^OrderStatus.final())
    |> order_by([o], desc: o.inserted_at)
    |> preload(:items)
    |> Repo.all()
    |> Enum.filter(&OrderStatus.active?/1)
  end

  def get_order(id) do
    Order
    |> Repo.get(id)
    |> Repo.preload([:client, :items])
  end

  def update_order_details(order, attrs, actor \\ :system)

  def update_order_details(%Order{status: :crm}, _attrs, actor),
    do: Audit.track({:error, :order_locked}, actor, "order.details_changed")

  def update_order_details(%Order{} = order, attrs, actor) do
    attrs =
      attrs
      |> Filter.normalize_params()
      |> Map.take(["status", "payment_method", "cancel_reason", "cancel_note"])

    changeset = Order.details_changeset(order, attrs)

    changeset
    |> persist([:order, :updated])
    |> Audit.track(actor, "order.details_changed", metadata: changeset.changes)
  end

  def update_order_crm(%Order{} = order, attrs) do
    order
    |> Order.crm_changeset(attrs)
    |> persist([:order, :updated])
  end

  def soft_delete_order(%Order{} = order, actor \\ :system) do
    order
    |> Order.changeset(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
    |> persist([:order, :deleted])
    |> Audit.track(actor, "order.deleted")
  end

  defp owned_by(session_id, nil), do: dynamic([o], o.session_id == ^session_id)
  defp owned_by(nil, client_id), do: dynamic([o], o.client_id == ^client_id)

  defp owned_by(session_id, client_id),
    do: dynamic([o], o.session_id == ^session_id or o.client_id == ^client_id)

  defp active_hours, do: Application.get_env(:delivest, :active_order_hours, 7)

  defp persist(changeset, event) do
    changeset
    |> Repo.update()
    |> Notifier.publish(event)
  end
end
