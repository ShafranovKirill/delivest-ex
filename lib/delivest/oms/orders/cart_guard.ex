defmodule Delivest.Oms.Orders.CartGuard do
  import Ecto.Query, warn: false

  alias Delivest.Oms.{Cart, CartView, Carts, Order}
  alias Delivest.Repo

  def acquire(cart_id, branch_id, order_id \\ nil) do
    with {:ok, cart_id} <- cast_id(cart_id),
         :ok <- lock(cart_id),
         :ok <- ensure_not_ordered(cart_id, order_id),
         {:ok, cart} <- fetch(cart_id),
         :ok <- ensure_branch(cart, branch_id) do
      {:ok, cart}
    end
  end

  defp cast_id(cart_id) do
    case Ecto.UUID.cast(cart_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :cart_not_found}
    end
  end

  defp lock(cart_id) do
    query = from(c in Cart, where: c.id == ^cart_id, lock: "FOR UPDATE", select: c.id)

    if Repo.one(query), do: :ok, else: {:error, :cart_not_found}
  end

  defp ensure_not_ordered(cart_id, order_id) do
    query = from(o in Order, where: o.cart_id == ^cart_id)
    query = if order_id, do: where(query, [o], o.id != ^order_id), else: query

    if Repo.exists?(query), do: {:error, :cart_already_ordered}, else: :ok
  end

  defp fetch(cart_id) do
    case Carts.get_cart_by_id(cart_id) do
      nil -> {:error, :cart_not_found}
      %CartView{items: []} -> {:error, :cart_is_empty}
      %CartView{} = cart -> {:ok, cart}
    end
  end

  defp ensure_branch(_cart, nil), do: :ok
  defp ensure_branch(%CartView{branch_id: branch_id}, branch_id), do: :ok
  defp ensure_branch(_cart, _branch_id), do: {:error, :cart_branch_mismatch}
end
