defmodule Delivest.Integrations.YandexDelivery.Claim do
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.YandexDelivery.Settings
  alias Delivest.Oms.Order
  alias Delivest.Oms.Order.Address

  @source 1
  @destination 2

  def build(
        %Order{} = order,
        %Branch{info: %BranchInfo{} = info} = branch,
        %Settings{} = settings
      ) do
    with {:ok, source} <- source_point(branch, info, settings, order),
         {:ok, destination} <- destination_point(order, settings) do
      {:ok,
       %{
         items: items(order),
         route_points: [source, destination],
         emergency_contact: source.contact |> Map.delete(:email),
         client_requirements: %{taxi_class: to_string(settings.taxi_class)},
         comment: comment(order),
         referral_source: "delivest"
       }
       |> put_auto_accept(settings)}
    end
  end

  def build(_order, _branch, _settings), do: {:error, :branch_address_missing}

  def collects_payment?(%Order{payment_method: method}), do: method in [:cash, :card_offline]

  defp source_point(branch, info, settings, order) do
    phone = settings.contact_phone || info.phone_number

    cond do
      blank?(info.address) or is_nil(info.latitude) or is_nil(info.longitude) ->
        {:error, :branch_address_missing}

      blank?(phone) ->
        {:error, :branch_phone_missing}

      true ->
        {:ok,
         %{
           point_id: @source,
           visit_order: 1,
           type: "source",
           should_notify_on_order_readiness: true,
           contact: %{
             name: settings.contact_name || branch.name,
             phone: phone,
             email: settings.contact_email
           },
           address:
             compact(%{
               fullname: Enum.join(Enum.reject([info.city, info.address], &blank?/1), ", "),
               city: info.city,
               coordinates: [info.longitude, info.latitude],
               comment: label(order)
             }),
           skip_confirmation: not settings.confirm_codes
         }}
    end
  end

  defp destination_point(%Order{address: %Address{} = address} = order, settings) do
    phone = order.customer_phone

    cond do
      blank?(address.street) or blank?(address.house) -> {:error, :address_missing}
      blank?(phone) -> {:error, :customer_phone_missing}
      true -> {:ok, destination(order, address, phone, settings)}
    end
  end

  defp destination_point(_order, _settings), do: {:error, :address_missing}

  defp destination(order, address, phone, settings) do
    house = Address.house_line(address)

    %{
      point_id: @destination,
      visit_order: 2,
      type: "destination",
      contact: %{name: order.customer_name || "Клиент", phone: phone},
      address:
        compact(%{
          fullname:
            Enum.join(Enum.reject([address.city, address.street, house], &blank?/1), ", "),
          city: address.city,
          street: address.street,
          building: house,
          coordinates: coordinates(address),
          porch: address.entrance,
          sfloor: address.floor,
          sflat: address.apartment,
          door_code: address.intercom,
          comment: address.comment
        }),
      external_order_id: order.number,
      skip_confirmation: not settings.confirm_codes
    }
    |> put_payment(order)
  end

  defp put_auto_accept(body, %Settings{auto_accept: true}), do: Map.put(body, :auto_accept, true)
  defp put_auto_accept(body, _settings), do: body

  defp put_payment(point, order) do
    if collects_payment?(order),
      do: Map.put(point, :payment_on_delivery, %{payment_method: "card"}),
      else: point
  end

  defp items(order) do
    goods =
      Enum.map(
        order.items,
        &%{
          title: Delivest.Oms.OrderItem.full_title(&1),
          quantity: &1.quantity,
          price: &1.price
        }
      )

    lines =
      if collects_payment?(order),
        do: fit(goods, order.total_amount - (order.delivery_amount || 0)) ++ delivery(order),
        else: goods

    fiscal = Delivest.Fiscal.settings(order.branch_id)
    Enum.map(lines, &item(&1, order, fiscal))
  end

  defp delivery(%Order{delivery_amount: amount}) when is_integer(amount) and amount > 0,
    do: [%{title: "Доставка", quantity: 1, price: amount, service: true}]

  defp delivery(_order), do: []

  defp fit(lines, target) do
    total = Enum.sum(Enum.map(lines, &(&1.price * &1.quantity)))

    if total == target or total == 0 or target < 0,
      do: lines,
      else: scale(lines, total, target)
  end

  defp scale(lines, total, target) do
    scaled =
      Enum.map(lines, fn line ->
        %{
          title: "#{line.title} × #{line.quantity}",
          quantity: 1,
          price: div(line.price * line.quantity * target, total)
        }
      end)

    rest = target - Enum.sum(Enum.map(scaled, & &1.price))
    List.update_at(scaled, -1, &%{&1 | price: &1.price + rest})
  end

  defp item(line, order, settings) do
    %{
      extra_id: order.number,
      pickup_point: @source,
      dropoff_point: @destination,
      title: line.title,
      quantity: line.quantity,
      cost_value: money(line.price),
      cost_currency: "RUB"
    }
    |> put_fiscalization(line, order, settings)
  end

  defp put_fiscalization(item, line, order, settings) do
    if collects_payment?(order) do
      Map.put(item, :fiscalization, %{
        vat_code_str: vat_code(if(line[:service], do: settings.delivery_vat, else: settings.vat)),
        item_type: if(line[:service], do: "service", else: "product")
      })
    else
      item
    end
  end

  defp vat_code(:none), do: "vat_none"
  defp vat_code(rate), do: to_string(rate)

  defp comment(%Order{comment: comment} = order) do
    Enum.join(Enum.reject([label(order), comment], &blank?/1), ". ")
  end

  defp label(%Order{number: number} = order),
    do: "Заказ №#{Order.short_number(order)} (#{number})"

  defp coordinates(%Address{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: [lon, lat]

  defp coordinates(_address), do: nil

  defp money(amount), do: :erlang.float_to_binary(amount / 100, decimals: 2)

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> blank?(value) end) |> Map.new()

  defp blank?(value), do: value in [nil, ""]
end
