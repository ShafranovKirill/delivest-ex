defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false

  alias Delivest.Audit
  alias Delivest.Oms.Order
  alias Delivest.Oms.Orders.{Create, DraftCart, Filter, Notifier, Update}
  alias Delivest.Repo

  defdelegate subscribe, to: Notifier
  defdelegate create_order(attrs, opts \\ []), to: Create, as: :run
  defdelegate update_order(order, attrs, opts \\ []), to: Update, as: :run
  defdelegate create_draft_cart(order), to: DraftCart, as: :create
  defdelegate populate_cart_from_order(order, cart_id), to: DraftCart, as: :populate

  def list_orders(params \\ %{}) do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> Filter.apply_filters(Filter.normalize_params(params))
    |> preload([:items, :client])
    |> Repo.all()
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
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
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
    attrs = attrs |> Filter.normalize_params() |> Map.take(["status", "payment_method"])
    changeset = Order.details_changeset(order, attrs)

    changeset
    |> persist([:order, :updated])
    |> Audit.track(actor, "order.details_changed", metadata: changeset.changes)
  end

  def update_order_crm_info(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> persist([:order, :updated])
  end

  def soft_delete_order(%Order{} = order, actor \\ :system) do
    order
    |> Order.changeset(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
    |> persist([:order, :deleted])
    |> Audit.track(actor, "order.deleted")
  end

  defp persist(changeset, event) do
    changeset
    |> Repo.update()
    |> Notifier.publish(event)
  end
end
