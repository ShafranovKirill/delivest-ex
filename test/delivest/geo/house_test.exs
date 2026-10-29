defmodule Delivest.Geo.HouseTest do
  use ExUnit.Case, async: true

  alias Delivest.Geo.House

  test "splits the block and the building from the house" do
    assert House.split("10") == %{house: "10", block: nil, building: nil}
    assert House.split("10А") == %{house: "10А", block: nil, building: nil}
    assert House.split("10 к 2") == %{house: "10", block: "2", building: nil}
    assert House.split("10к2") == %{house: "10", block: "2", building: nil}
    assert House.split("10 корп 2 стр 1") == %{house: "10", block: "2", building: "1"}
    assert House.split("10 стр 3") == %{house: "10", block: nil, building: "3"}
    assert House.split("") == %{house: nil, block: nil, building: nil}
  end

  test "joins the parts back into one line" do
    assert House.line(%{house: "10", block: "2", building: "1"}) == "10 к 2 стр 1"
    assert House.line(%{house: "10", block: nil, building: nil}) == "10"
    assert House.line(nil) == nil
  end
end
