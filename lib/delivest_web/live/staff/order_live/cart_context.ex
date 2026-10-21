defmodule DelivestWeb.Staff.OrderLive.CartContext do
  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.CartView

  def sync(%CartView{id: nil} = cart, _params), do: cart

  def sync(%CartView{} = cart, params) do
    desired = %{
      fulfillment_type: fulfillment(params, cart),
      client_id: client_id(params["customer_phone"])
    }

    current = %{fulfillment_type: cart.fulfillment_type, client_id: cart.client_id}

    if desired == current do
      cart
    else
      case Oms.update_cart_context(cart.id, desired) do
        {:ok, updated} -> updated
        _error -> cart
      end
    end
  end

  defp fulfillment(%{"fulfillment_type" => type}, _cart) when type in ~w(delivery pickup dine_in),
    do: type

  defp fulfillment(_params, cart), do: cart.fulfillment_type

  defp client_id(phone) when is_binary(phone) do
    with true <- Regex.match?(Identity.phone_regex(), phone),
         %{id: id} <- Identity.get_active_client_by_phone(phone) do
      id
    else
      _ -> nil
    end
  end

  defp client_id(_phone), do: nil
end
