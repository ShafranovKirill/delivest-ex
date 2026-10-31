defmodule Delivest.Loyalty.Rewards do
  alias Delivest.{Loyalty, Net}
  alias Delivest.Oms.CartView
  alias Delivest.Promo.Line

  def price(result, cart, client_id, reserved \\ 0) do
    items = CartView.star_items(cart)

    if items == [] do
      {:ok, result}
    else
      products = Net.list_products_by_ids(Enum.map(items, & &1.product_id))

      valid =
        Enum.all?(items, fn item ->
          case products[item.product_id] do
            %{stars_price: price} when is_integer(price) and price > 0 -> true
            _ -> false
          end
        end)

      if client_id && Loyalty.shop_enabled?(cart.branch_id) && valid do
        lines =
          Enum.map(items, fn item ->
            product = Map.fetch!(products, item.product_id)

            %Line{
              key: item.key,
              product_id: product.id,
              name: product.name,
              image_url: item.image_url,
              base_price: product.price,
              quantity: item.quantity,
              total: 0,
              stars: product.stars_price
            }
          end)

        stars = Enum.sum(Enum.map(lines, &(&1.stars * &1.quantity)))
        subtotal = Enum.sum(Enum.map(lines, &(&1.base_price * &1.quantity)))

        if Loyalty.balance(client_id) + reserved >= result.points + stars do
          {:ok,
           %{
             result
             | lines: result.lines ++ lines,
               points: result.points + stars,
               subtotal: result.subtotal + subtotal,
               discount: result.discount + subtotal
           }}
        else
          {:error, :insufficient_points}
        end
      else
        {:error, :points_unavailable}
      end
    end
  end
end
