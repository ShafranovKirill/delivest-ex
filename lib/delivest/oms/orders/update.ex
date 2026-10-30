defmodule Delivest.Oms.Orders.Update do
  import Ecto.Query, warn: false

  alias Delivest.Audit
  alias Delivest.Oms.{Carts, Order, OrderEvents, OrderLock}

  alias Delivest.Oms.Orders.{
    Assembler,
    Attrs,
    CartGuard,
    ClientResolver,
    DeliveryFee,
    Lines,
    Notifier,
    Pricing
  }

  alias Delivest.{Payments, Promo, Repo}
  alias Ecto.Multi

  @protected ["number", "staff_id", "branch_id"]

  def run(order, attrs, opts \\ [])

  def run(%Order{channel: %{}} = order, attrs, opts) do
    attrs = Attrs.normalize(attrs)
    actor = Keyword.get(opts, :actor, :system)

    Multi.new()
    |> Multi.run(:lock, fn _, _ -> lock_editable(order) end)
    |> Multi.run(:editable, fn _, %{lock: locked} -> editable(locked) end)
    |> Multi.update(:order, fn %{lock: locked} ->
      Ecto.Changeset.change(locked, comment: attrs["comment"])
    end)
    |> Multi.run(:event, fn repo, %{lock: locked, order: updated} ->
      OrderEvents.updated(repo, locked, updated, actor)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> Notifier.publish({:ok, order}, [:order, :updated])
      {:error, step, reason, _} -> {:error, step, reason}
    end
    |> Audit.track(actor, "order.updated")
  end

  def run(%Order{} = order, attrs, opts) do
    attrs = attrs |> Attrs.normalize() |> Map.drop(@protected)

    Multi.new()
    |> Multi.run(:lock, fn _, _ -> lock_editable(order) end)
    |> Multi.run(:editable, fn _, %{lock: locked} -> editable(locked) end)
    |> Multi.run(:client_id, fn _, _ -> ClientResolver.resolve(attrs) end)
    |> Multi.run(:cart, fn _, _ ->
      CartGuard.acquire(attrs["cart_id"], order.branch_id, order.id)
    end)
    |> Multi.run(:pricing, fn _, %{cart: cart, client_id: client_id} ->
      Pricing.run(cart, attrs, client_id, order)
    end)
    |> Multi.run(:delivery, fn _, %{pricing: pricing} ->
      DeliveryFee.run(order.branch_id, attrs, pricing, [source: "staff"], order)
    end)
    |> Multi.run(:lines, fn _, %{pricing: pricing} -> Lines.from_pricing(pricing) end)
    |> Multi.update(:order, &Assembler.changeset(order, attrs, &1))
    |> Multi.run(:allowed, fn _, %{lock: locked, order: updated} -> allowed(locked, updated) end)
    |> Multi.run(:payments, fn repo, %{order: updated} -> Payments.sync(repo, updated) end)
    |> Multi.run(:event, fn repo, %{order: updated} ->
      OrderEvents.updated(repo, order, updated, Keyword.get(opts, :actor, :system))
    end)
    |> Multi.run(:redemptions, fn _, %{order: order, pricing: pricing} ->
      Promo.redeem(order, pricing)
    end)
    |> Multi.run(:detached_cart, fn _, %{cart: cart} -> Carts.detach_cart(cart) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> Notifier.publish({:ok, order}, [:order, :updated])
      {:error, step, reason, _} -> {:error, step, reason}
    end
    |> Audit.track(Keyword.get(opts, :actor, :system), "order.updated")
  end

  defp lock_editable(%Order{id: id}) do
    query = from(o in Order, where: o.id == ^id and is_nil(o.deleted_at), lock: "FOR UPDATE")

    case Repo.one(query) do
      nil -> {:error, :order_not_found}
      order -> {:ok, Repo.preload(order, items: :modifiers)}
    end
  end

  defp editable(order) do
    with :ok <- OrderLock.editable(order), do: {:ok, order}
  end

  defp allowed(old, new) do
    fields = old |> OrderEvents.changes(new) |> Map.keys()
    with :ok <- OrderLock.check_changes(old, new, fields), do: {:ok, fields}
  end
end
