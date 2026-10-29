defmodule Delivest.Integrations.YandexEda.Price do
  alias Delivest.Integrations.Channels.ChannelProduct
  alias Delivest.Integrations.YandexEda.BranchSettings
  alias Delivest.Money

  def of(_product, %ChannelProduct{price: price}, _settings) when is_integer(price), do: price

  def of(%{price: base}, _channel_product, %BranchSettings{markup_percent: markup, round_to: step})
      when markup > 0,
      do: base |> Kernel.*(100 + markup) |> ceil_div(100) |> Money.round_up(step * 100)

  def of(%{price: base}, _channel_product, _settings), do: base

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
