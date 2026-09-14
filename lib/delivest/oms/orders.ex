defmodule Delivest.Oms.Orders do
  import Ecto.Query, warn: false
  alias Delivest.Net
  alias Ecto.Multi
  alias Delivest.Repo
  alias Delivest.Oms.Order
  alias Delivest.Oms.Order.OrderNumber

  alias Delivest.Identity
  alias Delivest.Oms.Carts

  def create_order(attrs) do
    Multi.new()
    |> Multi.run(:client, fn _repo, _ ->
      get_or_create_client(attrs)
    end)
    |> Multi.run(:cart, fn _repo, _ ->
      fetch_cart(attrs["cart_id"])
    end)
    |> Multi.run(:products, fn _repo, %{cart: cart} ->
      fetch_products_for_cart(cart)
    end)
    |> Multi.run(:order_number, fn _repo, _ ->
      OrderNumber.generate()
    end)
    |> Multi.insert(:order, fn %{
                                 client: client,
                                 cart: cart,
                                 products: products,
                                 order_number: number
                               } ->
      build_order_changeset(number, client, cart, products, attrs)
    end)
    |> Multi.run(:clear_cart, fn _repo, %{cart: cart} ->
      Carts.delete_cart(cart.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, Repo.preload(order, :items)}
      {:error, step, reason, _changes} -> {:error, step, reason}
    end
  end

  defp get_or_create_client(%{"phone" => phone} = attrs) when not is_nil(phone) do
    client_attrs = %{name: Map.get(attrs, "client_name")}
    {:ok, Identity.get_or_create_client_by_phone(phone, client_attrs)}
  end

  defp get_or_create_client(_), do: {:ok, nil}

  defp fetch_cart(cart_id) do
    case Carts.get_cart(id: cart_id) do
      nil -> {:error, :cart_not_found}
      %{items: []} -> {:error, :cart_is_empty}
      cart -> {:ok, cart}
    end
  end

  defp fetch_products_for_cart(cart) do
    product_ids = Enum.map(cart.items, & &1.product_id)
    products = Net.list_products_by_ids(product_ids, [])

    products_map = Map.new(products, &{&1.id, &1})
    {:ok, products_map}
  end

  defp build_order_changeset(number, client, cart, products_map, attrs) do
    {items_attrs, total_amount} =
      Enum.reduce(cart.items, {[], 0}, fn item, {acc_items, acc_total} ->
        product = Map.get(products_map, item.product_id)

        price = product.price
        item_total = price * item.quantity

        order_item = %{
          product_id: item.product_id,
          title: product.title,
          price: price,
          quantity: item.quantity
        }

        {[order_item | acc_items], acc_total + item_total}
      end)

    order_params =
      attrs
      |> Map.put("number", number)
      |> Map.put("total_amount", total_amount)
      |> Map.put("branch_id", cart.branch_id)
      |> Map.put("staff_id", cart.staff_id)
      |> Map.put("client_id", client && client.id)

    %Order{}
    |> Order.changeset(order_params)
    |> Ecto.Changeset.put_assoc(:items, items_attrs)
  end
end
