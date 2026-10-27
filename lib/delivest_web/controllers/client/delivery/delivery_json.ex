defmodule DelivestWeb.Client.Delivery.DeliveryJSON do
  def quote(%{quote: quote}), do: %{data: quote}
end
