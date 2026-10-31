defmodule Delivest.OrderFixtures do
  import Delivest.Factory

  alias Delivest.Oms.{Carts, Orders}

  def order_fixture(branch_id, opts \\ []) do
    price = Keyword.get(opts, :price, 15_000)
    quantity = Keyword.get(opts, :quantity, 1)

    product =
      Keyword.get_lazy(opts, :product, fn -> insert_branch_product(branch_id, price: price) end)

    {:ok, cart} =
      Carts.create_cart(%{
        session_id: "fx-#{System.unique_integer([:positive])}",
        branch_id: branch_id
      })

    {:ok, _, _} = Carts.add_item(cart.id, product.id, quantity)

    attrs =
      Map.merge(
        %{
          "cart_id" => cart.id,
          "branch_id" => branch_id,
          "fulfillment_type" => "pickup",
          "payment_method" => "cash"
        },
        Keyword.get(opts, :attrs, %{})
      )

    {:ok, order} = Orders.create_order(attrs)
    order
  end
end
