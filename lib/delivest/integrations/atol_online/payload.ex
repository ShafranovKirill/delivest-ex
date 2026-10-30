defmodule Delivest.Integrations.AtolOnline.Payload do
  @payment_types %{cash: 0, card: 1, prepayment: 2}
  @objects %{product: 1, excise: 2, service: 4}

  def build(receipt, external_id, callback_url, timestamp) do
    %{
      timestamp: Calendar.strftime(timestamp, "%d.%m.%Y %H:%M:%S"),
      external_id: external_id,
      service: %{callback_url: callback_url},
      receipt:
        compact(%{
          client: receipt.client,
          company: receipt.company,
          items: Enum.map(receipt.items, &item(&1, receipt.stage)),
          payments:
            Enum.map(receipt.payments, &%{type: @payment_types[&1.type], sum: rub(&1.sum)}),
          total: rub(receipt.total),
          cashier: receipt.cashier
        })
    }
  end

  defp item(line, stage) do
    %{
      name: line.name,
      price: rub(line.price),
      quantity: line.quantity,
      measure: 0,
      sum: rub(line.sum),
      payment_method: to_string(stage),
      payment_object: @objects[line.object],
      vat: %{type: to_string(line.vat)}
    }
  end

  defp rub(kopecks), do: Jason.Fragment.new(Decimal.to_string(Decimal.div(kopecks, 100), :normal))

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
