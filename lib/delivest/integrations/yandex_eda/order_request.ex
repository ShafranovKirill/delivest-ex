defmodule Delivest.Integrations.YandexEda.OrderRequest do
  alias Delivest.Integrations.YandexEda.{Clock, OrderItems}

  @discriminators ~w(yandex marketplace pickup)
  @target_fields %{
    "yandex" => "courierArrivementDate",
    "marketplace" => "deliveryDate",
    "pickup" => "clientArrivementDate"
  }

  defstruct [
    :eats_id,
    :restaurant_id,
    :discriminator,
    :platform,
    :comment,
    :persons,
    :client_name,
    :phone,
    :pickup_code,
    :target_at,
    :paid,
    :items_cost,
    :delivery_fee,
    :change,
    :address,
    items: [],
    raw: %{}
  ]

  def parse(%{"discriminator" => discriminator} = params) when discriminator in @discriminators do
    delivery = map(params["deliveryInfo"])
    payment = map(params["paymentInfo"])

    with {:ok, eats_id} <- required(params, "eatsId"),
         {:ok, restaurant_id} <- required(params, "restaurantId"),
         {:ok, items} <- OrderItems.parse(params["items"]),
         {:ok, paid} <- paid(payment["paymentType"]),
         {:ok, items_cost} <- money(payment["itemsCost"], "paymentInfo.itemsCost"),
         {:ok, target_at} <- target_at(delivery, discriminator),
         {:ok, address} <- address(delivery, discriminator) do
      {:ok,
       %__MODULE__{
         eats_id: eats_id,
         restaurant_id: restaurant_id,
         discriminator: discriminator,
         platform: params["platform"],
         comment: text(params["comment"]),
         persons: params["persons"],
         client_name: text(delivery["clientName"]),
         phone: delivery["realPhoneNumber"] || delivery["phoneNumber"],
         pickup_code: delivery["pickupCode"],
         target_at: target_at,
         paid: paid,
         items_cost: items_cost,
         delivery_fee: optional_money(payment["deliveryFee"]),
         change: optional_money(payment["change"]),
         address: address,
         items: items,
         raw: params
       }}
    end
  end

  def parse(_params), do: {:error, "discriminator must be yandex, marketplace or pickup"}

  defp required(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

  defp paid("CARD"), do: {:ok, true}
  defp paid("CASH"), do: {:ok, false}
  defp paid(_type), do: {:error, "paymentInfo.paymentType must be CARD or CASH"}

  defp money(value, _field) when is_number(value) and value >= 0, do: {:ok, floor(value)}
  defp money(_value, field), do: {:error, "#{field} is required"}

  defp optional_money(value) when is_number(value) and value > 0, do: floor(value)
  defp optional_money(_value), do: nil

  defp target_at(delivery, discriminator) do
    field = Map.fetch!(@target_fields, discriminator)

    case Clock.parse(delivery[field]) do
      {:ok, datetime} -> {:ok, datetime}
      :error -> {:error, "deliveryInfo.#{field} is required"}
    end
  end

  defp address(delivery, "marketplace") do
    with %{"full" => full, "latitude" => latitude, "longitude" => longitude} <-
           delivery["deliveryAddress"],
         {:ok, latitude} <- coordinate(latitude),
         {:ok, longitude} <- coordinate(longitude) do
      {:ok, %{full: full, latitude: latitude, longitude: longitude}}
    else
      _ -> {:error, "deliveryInfo.deliveryAddress is required"}
    end
  end

  defp address(_delivery, _discriminator), do: {:ok, nil}

  defp coordinate(value) when is_number(value), do: {:ok, value / 1}

  defp coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp coordinate(_value), do: :error

  defp map(value) when is_map(value), do: value
  defp map(_value), do: %{}

  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(_value), do: nil
end
