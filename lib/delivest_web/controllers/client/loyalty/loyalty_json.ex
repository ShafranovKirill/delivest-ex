defmodule DelivestWeb.Client.Loyalty.LoyaltyJSON do
  def show(%{enabled: enabled, balance: balance, history: history, products: products}) do
    %{
      data: %{
        enabled: enabled,
        balance: balance,
        history: Enum.map(history, &entry/1),
        products: Enum.map(products, &%{id: &1.id, name: &1.name, stars_price: &1.stars_price})
      }
    }
  end

  defp entry(entry) do
    %{
      id: entry.id,
      kind: entry.kind,
      amount: entry.amount,
      order_id: entry.order_id,
      expires_at: entry.expires_at,
      inserted_at: entry.inserted_at
    }
  end
end
