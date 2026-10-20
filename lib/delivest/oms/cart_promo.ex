defmodule Delivest.Oms.CartPromo do
  alias Delivest.Oms.{CartPricing, Carts, CartView}
  alias Delivest.Promo.PromoCode

  def apply_code(cart_id, code) do
    with %CartView{} = view <- Carts.get_cart_by_id(cart_id) || {:error, :cart_not_found},
         {:ok, code} <- normalize(code),
         :ok <- accept(CartPricing.apply(view, code: code).code) do
      Carts.update_context(cart_id, %{promo_code: code})
    end
  end

  def remove_code(cart_id), do: Carts.update_context(cart_id, %{promo_code: nil})

  def set_fulfillment(cart_id, fulfillment_type),
    do: Carts.update_context(cart_id, %{fulfillment_type: fulfillment_type})

  def bind_client(%CartView{client_id: client_id} = view, client_id), do: {:ok, view}

  def bind_client(%CartView{id: cart_id}, client_id),
    do: Carts.update_context(cart_id, %{client_id: client_id})

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
