defmodule Delivest.Integrations.YandexEda.PriceTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Channels.ChannelProduct
  alias Delivest.Integrations.YandexEda.{BranchSettings, Price}

  @product %{price: 333}

  test "the channel price wins over the markup" do
    settings = %BranchSettings{markup_percent: 20, round_to: 10}
    assert Price.of(@product, %ChannelProduct{price: 290}, settings) == 290
  end

  test "the markup is rounded up to the step" do
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 1}) == 367
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 5}) == 370
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 10}) == 370
    assert Price.of(%{price: 100}, nil, %BranchSettings{markup_percent: 10, round_to: 10}) == 110
  end

  test "without a markup or own price the base price is kept" do
    assert Price.of(@product, nil, %BranchSettings{}) == 333
    assert Price.of(@product, %ChannelProduct{price: nil}, %BranchSettings{}) == 333
  end
end
