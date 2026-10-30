defmodule Delivest.Integrations.Rkeeper.OrderPayload do
  alias Delivest.Integrations.Rkeeper.Settings
  alias Delivest.Oms.{Order, OrderItem}

  @payments %{cash: "cash", card_offline: "card", online: "online"}

  def build(%Order{} = order, %Settings{} = settings, articles) do
    with {:ok, products} <- products(order.items, articles),
         {:ok, payment} <- Map.fetch(@payments, order.payment_method) |> payment_type() do
      expedition = if order.fulfillment_type == :delivery, do: "delivery", else: "pickup"
      time = expected_time(order)

      {:ok,
       compact(%{
         originalOrderId: order.number,
         customer: compact(%{name: order.customer_name, phone: order.customer_phone}),
         expeditionType: expedition,
         delivery: delivery(order, time),
         pickup: if(expedition == "pickup", do: %{expectedTime: time, taker: "customer"}),
         payment: %{type: payment},
         prePayments: prepayments(order, settings),
         products: products,
         price: %{total: money(order.total_amount)},
         personsQuantity: order.persons,
         comment: order.comment,
         orderCategoryCode: code(settings, expedition, :category),
         orderTypeCode: code(settings, expedition, :type)
       })}
    end
  end

  def expected_time(%Order{} = order) do
    (order.cook_by || DateTime.utc_now(:second))
    |> Delivest.LocalTime.local(order.branch_id)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp payment_type({:ok, type}), do: {:ok, type}
  defp payment_type(:error), do: {:error, :unsupported_payment}

  defp products(items, articles) do
    Enum.reduce_while(items, {:ok, []}, fn %OrderItem{} = item, {:ok, acc} ->
      with {:ok, id} <- article(articles.products, item.product_id),
           {:ok, ingredients} <- ingredients(item, articles.modifiers) do
        product =
          compact(%{
            id: id,
            name: item.title,
            price: money(item.price),
            quantity: item.quantity,
            ingredients: ingredients
          })

        {:cont, {:ok, [product | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, products} -> {:ok, Enum.reverse(products)}
      error -> error
    end)
  end

  defp ingredients(%OrderItem{modifiers: modifiers}, articles) when is_list(modifiers) do
    Enum.reduce_while(modifiers, {:ok, []}, fn modifier, {:ok, acc} ->
      case article(articles, modifier.modifier_id) do
        {:ok, id} ->
          ingredient = %{
            id: id,
            name: modifier.name,
            quantity: modifier.quantity,
            price: money(modifier.price)
          }

          {:cont, {:ok, [ingredient | acc]}}

        error ->
          {:halt, error}
      end
    end)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end)
  end

  defp ingredients(_item, _articles), do: {:ok, []}

  defp article(articles, id) do
    case Map.get(articles, id) do
      nil -> {:error, {:missing_external_id, id}}
      external_id -> {:ok, external_id}
    end
  end

  defp delivery(%Order{fulfillment_type: :delivery, address: %{} = address}, time) do
    %{
      expectedTime: time,
      address:
        compact(%{
          fullAddress: address.formatted,
          city: address.city && %{name: address.city},
          street: address.street && %{name: address.street},
          houseNumber: Delivest.Geo.House.line(address),
          flatNumber: address.apartment,
          entrance: address.entrance,
          intercom: address.intercom,
          floor: address.floor,
          comment: address.comment,
          coordinates: coordinates(address)
        })
    }
  end

  defp delivery(_order, _time), do: nil

  defp coordinates(%{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do: %{latitude: lat, longitude: lng}

  defp coordinates(_address), do: nil

  defp prepayments(%Order{payment_method: :online, total_amount: total}, settings)
       when total > 0,
       do: [compact(%{amount: money(total), currency: settings.prepay_currency})]

  defp prepayments(_order, _settings), do: nil

  defp code(settings, "delivery", :category), do: integer(settings.delivery_category_code)
  defp code(settings, "delivery", :type), do: integer(settings.delivery_type_code)
  defp code(settings, _pickup, :category), do: integer(settings.pickup_category_code)
  defp code(settings, _pickup, :type), do: integer(settings.pickup_type_code)

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> value
    end
  end

  defp integer(value), do: value

  defp money(kopecks), do: kopecks / 100

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, "", [], %{}] end)
end
