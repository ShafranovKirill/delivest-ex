defmodule DelivestWeb.Client.Loyalty.LoyaltyJSON do
  def show(%{enabled: enabled, balance: balance, history: history}) do
    %{data: %{enabled: enabled, balance: balance, history: Enum.map(history, &entry/1)}}
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
