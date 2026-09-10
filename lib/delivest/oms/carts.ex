defmodule Delivest.Carts do
  import Ecto.Query, warn: false

  alias Delivest.Repo
  alias Delivest.Oms.{Cart, CartItem}

  def get_cart(opts) when is_list(opts) do
    session_id = Keyword.get(opts, :session_id)
    staff_id = Keyword.get(opts, :staff_id)

    query = from(c in Cart, preload: [:items])

    cond do
      not is_nil(session_id) ->
        Repo.one(from c in query, where: c.session_id == ^session_id)

      not is_nil(staff_id) ->
        Repo.one(from c in query, where: c.staff_id == ^staff_id)

      true ->
        nil
    end
  end

  def add_item(%Cart{} = cart, product_id) do
    case Repo.get_by(CartItem, cart_id: cart.id, product_id: product_id) do
      nil ->
        %CartItem{}
        |> CartItem.changeset(%{
          cart_id: cart.id,
          product_id: product_id,
          quantity: 1
        })
        |> Repo.insert()

      %CartItem{} = item ->
        item
        |> CartItem.changeset(%{quantity: item.quantity + 1})
        |> Repo.update()
    end
  end

  def remove_item(%Cart{} = cart, product_id, opts \\ []) do
    delete_all? = Keyword.get(opts, :all, false)

    case Repo.get_by(CartItem, cart_id: cart.id, product_id: product_id) do
      nil ->
        {:error, :not_found}

      %CartItem{} = item ->
        if delete_all? or item.quantity <= 1 do
          Repo.delete(item)
        else
          item
          |> CartItem.changeset(%{quantity: item.quantity - 1})
          |> Repo.update()
        end
    end
  end
end
