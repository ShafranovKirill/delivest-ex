defmodule DelivestWeb.Client.Order.OrderJSON do
  def create(%{order: order}) do
    %{data: order_data(order)}
  end

  defp order_data(order) do
    %{
      id: order.id,
      number: order.number,
      status: order.status,
      fulfillment_type: order.fulfillment_type,
      payment_method: order.payment_method,
      total_amount: order.total_amount,
      branch_id: order.branch_id,
      cart_id: order.cart_id,
      client_id: order.client_id,
      comment: order.comment,
      customer_phone: order.customer_phone || customer_phone(order),
      customer_name: order.customer_name || customer_name(order),
      address: serialize_address(order.address),
      items: Enum.map(order.items || [], &item_data/1)
    }
  end

  defp item_data(item) do
    %{
      product_id: item.product_id,
      title: item.title,
      price: item.price,
      quantity: item.quantity
    }
  end

  defp customer_phone(%{client: %_{phone: phone}}), do: phone
  defp customer_phone(_), do: nil

  defp customer_name(%{client: %_{name: name}}), do: name
  defp customer_name(_), do: nil

  defp serialize_address(%Ecto.Changeset{} = _address), do: nil
  defp serialize_address(%{} = address), do: Map.from_struct(address)
  defp serialize_address(_), do: nil
end
