defmodule Delivest.Integrations.Iiko.OrderPayload do
  alias Delivest.Integrations.Iiko.Settings
  alias Delivest.Oms.{Order, OrderItem}

  @source_key "delivest"
  @kinds %{cash: "Cash", card_offline: "Card", online: "External"}

  def build(%Order{} = order, %Settings{} = settings, articles) do
    with {:ok, items} <- items(order.items, articles),
         {:ok, payments} <- payments(order, settings) do
      {:ok,
       %{
         id: order.id,
         externalNumber: order.number,
         completeBefore: complete_before(order),
         phone: order.customer_phone,
         phoneExtension: order.customer_phone_ext,
         customer: customer(order),
         orderServiceType: service_type(order),
         deliveryPoint: delivery_point(order),
         comment: order.comment,
         items: items,
         payments: payments,
         guests: order.persons && %{count: order.persons},
         sourceKey: @source_key
       }
       |> compact()}
    end
  end

  def complete_before(%Order{cook_by: nil}), do: nil

  def complete_before(%Order{cook_by: cook_by, branch_id: branch_id}) do
    cook_by
    |> Delivest.LocalTime.local(branch_id)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S.%f")
    |> String.slice(0..-4//1)
  end

  def money(kopecks), do: kopecks / 100

  defp items(items, articles) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case item(item, articles) do
        {:ok, built} -> {:cont, {:ok, [built | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, built} -> {:ok, Enum.reverse(built)}
      error -> error
    end)
  end

  defp item(%OrderItem{} = item, articles) do
    modifiers = if is_list(item.modifiers), do: item.modifiers, else: []

    with {:ok, product_id} <- article(articles.products, item.product_id),
         {:ok, size, modifiers} <- split_size(modifiers, articles.modifiers),
         {:ok, modifiers} <- modifiers(modifiers, articles.modifiers) do
      {:ok,
       compact(%{
         type: "Product",
         productId: product_id,
         productSizeId: size,
         amount: item.quantity,
         price: money(item.price),
         modifiers: modifiers
       })}
    end
  end

  defp split_size(modifiers, articles) do
    case Enum.split_with(modifiers, &match?(%{size: true}, Map.get(articles, &1.modifier_id))) do
      {[], rest} ->
        {:ok, nil, rest}

      {[size | _], rest} ->
        {:ok, articles[size.modifier_id].external_id, rest}
    end
  end

  defp modifiers(modifiers, articles) do
    Enum.reduce_while(modifiers, {:ok, []}, fn modifier, {:ok, acc} ->
      case Map.get(articles, modifier.modifier_id) do
        %{external_id: id} = article ->
          built =
            compact(%{
              productId: id,
              productGroupId: article[:group_id],
              amount: modifier.quantity,
              price: money(modifier.price)
            })

          {:cont, {:ok, [built | acc]}}

        nil ->
          {:halt, {:error, {:missing_external_id, modifier.modifier_id}}}
      end
    end)
    |> then(fn
      {:ok, built} -> {:ok, Enum.reverse(built)}
      error -> error
    end)
  end

  defp article(articles, product_id) do
    case Map.get(articles, product_id) do
      nil -> {:error, {:missing_external_id, product_id}}
      external_id -> {:ok, external_id}
    end
  end

  defp payments(%Order{total_amount: total}, _settings) when total <= 0, do: {:ok, []}

  defp payments(%Order{payment_method: method, total_amount: total}, settings) do
    with {:ok, kind} <- Map.fetch(@kinds, method),
         id when is_binary(id) and id != "" <- payment_type_id(settings, method) do
      {:ok,
       [
         compact(%{
           paymentTypeKind: kind,
           paymentTypeId: id,
           sum: money(total),
           isProcessedExternally: method == :online,
           isFiscalizedExternally: method == :online
         })
       ]}
    else
      _missing -> {:error, {:missing_payment_type, method}}
    end
  end

  defp payment_type_id(settings, :cash), do: settings.cash_payment_type_id
  defp payment_type_id(settings, :card_offline), do: settings.card_payment_type_id
  defp payment_type_id(settings, :online), do: settings.online_payment_type_id

  defp customer(%Order{customer_name: name}) when is_binary(name) and name != "",
    do: %{name: name, type: "one-time"}

  defp customer(_order), do: %{type: "one-time"}

  defp service_type(%Order{fulfillment_type: :delivery}), do: "DeliveryByCourier"
  defp service_type(_order), do: "DeliveryByClient"

  defp delivery_point(%Order{fulfillment_type: :delivery, address: %{} = address}) do
    compact(%{
      coordinates: coordinates(address),
      address:
        compact(%{
          street: compact(%{name: address.street, city: address.city}),
          house: address.house,
          building: Enum.join(Enum.reject([address.block, address.building], &blank?/1), " "),
          flat: address.apartment,
          entrance: address.entrance,
          floor: address.floor,
          doorphone: address.intercom
        }),
      comment: address.comment
    })
  end

  defp delivery_point(_order), do: nil

  defp coordinates(%{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do: %{latitude: lat, longitude: lng}

  defp coordinates(_address), do: nil

  defp compact(map), do: Map.reject(map, fn {_key, value} -> blank?(value) end)

  defp blank?(value), do: value in [nil, "", [], %{}]
end
