defmodule Delivest.Oms.CartPromo do
  alias Delivest.Oms.{CartPricing, Carts, CartView}
  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Oms.Cart
  alias Delivest.Promo.PromoCode

  def apply_code(cart_id, code) do
    with %CartView{} = view <- Carts.get_cart_by_id(cart_id) || {:error, :cart_not_found},
         {:ok, code} <- normalize(code),
         :ok <- accept(CartPricing.apply(view, code: code).code) do
      change_code(cart_id, code)
    end
  end

  def remove_code(cart_id), do: change_code(cart_id, nil)

  def set_fulfillment(cart_id, fulfillment_type),
    do: Carts.update_context(cart_id, %{fulfillment_type: fulfillment_type})

  def bind_client(%CartView{client_id: client_id} = view, client_id), do: {:ok, view}

  def bind_client(%CartView{id: cart_id}, client_id),
    do: Carts.update_context(cart_id, %{client_id: client_id})

  def choose_gifts(cart_id, promotion_id, ids) do
    mutate(cart_id, fn cart ->
      view = cart |> Carts.build_cart_view() |> CartPricing.apply()
      promotion = Enum.find(view.promotions, &(&1.promotion_id == promotion_id))
      choice = promotion && promotion.gift_choice

      cond do
        is_nil(choice) ->
          Repo.rollback({:promo, :gift_not_available})

        not is_list(ids) ->
          Repo.rollback({:promo, :gift_invalid})

        ids != [] and not choice.available ->
          Repo.rollback({:promo, :gift_not_available})

        length(Enum.uniq(ids)) != length(ids) or
          (ids != [] and length(ids) != choice.required) or
            Enum.any?(ids, fn id -> not Enum.any?(choice.options, &(&1.product_id == id)) end) ->
          Repo.rollback({:promo, :gift_invalid})

        true ->
          choices = cart.promo_gifts || %{}

          choices =
            if ids == [],
              do: Map.delete(choices, promotion_id),
              else: Map.put(choices, promotion_id, ids)

          %{promo_gifts: choices}
      end
    end)
  end

  defp change_code(cart_id, code) do
    mutate(cart_id, fn cart ->
      choices = cart.promo_gifts || %{}
      old = if cart.promo_code, do: Delivest.Promo.Codes.find(cart.branch_id, cart.promo_code)

      choices =
        if old && cart.promo_code != code,
          do: Map.delete(choices, old.promotion_id),
          else: choices

      %{promo_code: code, promo_gifts: choices}
    end)
  end

  defp mutate(cart_id, fun) do
    Repo.transaction(fn ->
      cart = Repo.one(from c in Cart, where: c.id == ^cart_id, lock: "FOR UPDATE")
      if is_nil(cart), do: Repo.rollback(:cart_not_found)
      cart |> Cart.context_changeset(fun.(cart)) |> Repo.update!()
    end)
    |> case do
      {:ok, _} ->
        Cachex.del(:cart_cache, cart_id)
        {:ok, cart_id |> Carts.build_cart_view() |> CartPricing.apply()}

      error ->
        error
    end
  end

  defp normalize(code) when is_binary(code) do
    case PromoCode.normalize(code) do
      "" -> {:error, {:promo, :not_found}}
      code -> {:ok, code}
    end
  end

  defp normalize(_code), do: {:error, {:promo, :not_found}}

  defp accept(%{status: :rejected, reason: reason}), do: {:error, {:promo, reason}}
  defp accept(_state), do: :ok
end
