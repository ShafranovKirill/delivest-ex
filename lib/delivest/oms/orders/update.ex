defmodule Delivest.Oms.Orders.Update do
  import Ecto.Query, warn: false

  alias Delivest.Audit
  alias Delivest.Oms.{Carts, Order}

  alias Delivest.Oms.Orders.{
    Assembler,
    Attrs,
    CartGuard,
    ClientResolver,
    Lines,
    Notifier,
    Pricing
  }

  alias Delivest.{Promo, Repo}
  alias Ecto.Multi

  @protected ["number", "staff_id", "branch_id"]

  def run(%Order{} = order, attrs, opts \\ []) do
    attrs = attrs |> Attrs.normalize() |> Map.drop(@protected)

    Multi.new()
    |> Multi.run(:lock, fn _, _ -> lock_editable(order) end)
    |> Multi.run(:client_id, fn _, _ -> ClientResolver.resolve(attrs) end)
    |> Multi.run(:cart, fn _, _ ->
      CartGuard.acquire(attrs["cart_id"], order.branch_id, order.id)
    end)
    |> Multi.run(:pricing, fn _, %{cart: cart, client_id: client_id} ->
      Pricing.run(cart, attrs, client_id, order)
    end)
    |> Multi.run(:lines, fn _, %{pricing: pricing} -> Lines.from_pricing(pricing) end)
    |> Multi.update(:order, &Assembler.changeset(order, attrs, &1))
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
    query =
      from(o in Order,
        where: o.id == ^id and is_nil(o.deleted_at),
        lock: "FOR UPDATE",
        select: o.status
      )

    case Repo.one(query) do
      nil -> {:error, :order_not_found}
      :crm -> {:error, :order_locked}
      _status -> {:ok, :locked}
    end
  end
end
