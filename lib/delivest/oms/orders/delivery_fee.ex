defmodule Delivest.Oms.Orders.DeliveryFee do
  alias Delivest.Delivery
  alias Delivest.Oms.Order

  @strict_sources ["app"]
  @quoted_sources ["app", "staff"]

  def run(branch_id, attrs, pricing, opts, order \\ nil) do
    source = Keyword.get(opts, :source, "staff")

    cond do
      Keyword.has_key?(opts, :delivery_amount) -> {:ok, opts[:delivery_amount] || 0}
      fulfillment(attrs, order) != "delivery" -> {:ok, 0}
      source not in @quoted_sources -> {:ok, 0}
      true -> quote(branch_id, address(attrs, order), pricing.total, source)
    end
  end

  defp quote(branch_id, address, total, source) do
    case {Delivery.quote(branch_id, point(address), total), source} do
      {{:ok, %{price: price}}, _source} ->
        {:ok, price}

      {{:error, :no_coordinates}, "app"} ->
        if blank?(address), do: {:ok, 0}, else: {:error, :no_coordinates}

      {{:error, reason}, source} when source in @strict_sources ->
        {:error, reason}

      {{:error, _reason}, _source} ->
        {:ok, 0}
    end
  end

  defp fulfillment(%{"fulfillment_type" => type}, _order) when type not in [nil, ""],
    do: to_string(type)

  defp fulfillment(_attrs, %Order{fulfillment_type: type}), do: to_string(type)
  defp fulfillment(_attrs, _order), do: nil

  defp address(%{"address" => address}, _order) when is_map(address), do: address
  defp address(_attrs, %Order{address: %{} = address}), do: Map.from_struct(address)
  defp address(_attrs, _order), do: %{}

  defp point(address) do
    with lat when is_number(lat) <- number(value(address, :latitude)),
         lng when is_number(lng) <- number(value(address, :longitude)) do
      {lat, lng}
    else
      _ -> nil
    end
  end

  defp blank?(address),
    do: Enum.all?([:street, :house, :formatted], &(value(address, &1) in [nil, ""]))

  defp value(address, key), do: Map.get(address, key) || Map.get(address, to_string(key))

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp number(_value), do: nil
end
