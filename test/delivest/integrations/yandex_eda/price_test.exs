defmodule Delivest.Integrations.YandexEda.PriceTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Channels.ChannelProduct
  alias Delivest.Integrations.YandexEda.{BranchSettings, Price}

  @product %{price: 33_350}

  test "the channel price wins over the markup" do
    settings = %BranchSettings{markup_percent: 20, round_to: 10}
    assert Price.of(@product, %ChannelProduct{price: 29_000}, settings) == 29_000
  end

  test "the markup is rounded up to the step" do
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 1}) == 36_700
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 5}) == 37_000
    assert Price.of(@product, nil, %BranchSettings{markup_percent: 10, round_to: 10}) == 37_000

    assert Price.of(%{price: 10_000}, nil, %BranchSettings{markup_percent: 10, round_to: 10}) ==
             11_000
  end

  test "without a markup or own price the base price is kept" do
    assert Price.of(@product, nil, %BranchSettings{}) == 33_350
    assert Price.of(@product, %ChannelProduct{price: nil}, %BranchSettings{}) == 33_350
  end
end
