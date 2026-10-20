defmodule Delivest.Oms.Orders.Pricing do
  alias Delivest.Oms.{CartView, Order}
  alias Delivest.Promo

  @default_fulfillment "dine_in"

  def run(%CartView{} = cart, attrs, client_id, order \\ nil) do
    result =
      cart
      |> CartView.base_items()
      |> Promo.price(%{
        branch_id: cart.branch_id,
        client_id: client_id,
        fulfillment_type: fulfillment(attrs, order),
        code: cart.promo_code,
        except_order_id: order && order.id
      })

    ensure_expected(result, attrs["expected_total"])
  end

  defp fulfillment(%{"fulfillment_type" => type}, _order) when type not in [nil, ""],
    do: to_string(type)

  defp fulfillment(_attrs, %Order{fulfillment_type: type}), do: to_string(type)
  defp fulfillment(_attrs, _order), do: @default_fulfillment

  defp ensure_expected(result, nil), do: {:ok, result}

  defp ensure_expected(result, expected) do
    case parse(expected) do
      {:ok, expected} when result.total > expected -> {:error, :price_changed}
      _ -> {:ok, result}
    end
  end

  defp parse(value) when is_integer(value), do: {:ok, value}

  defp parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse(_value), do: :error
end
