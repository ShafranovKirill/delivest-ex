defmodule Delivest.Oms.Order.AddressTest do
  use ExUnit.Case, async: true

  alias Delivest.Oms.Order.Address

  test "splits a one-line house into house, block and building" do
    address = Address.changeset(%Address{}, %{"house" => "10 к 2 стр 1"}).changes
    assert %{house: "10", block: "2", building: "1"} = address
  end

  test "keeps the parts when they are sent separately" do
    changes =
      Address.changeset(%Address{}, %{"house" => "10", "block" => "3", "building" => ""}).changes

    assert changes.house == "10"
    assert changes.block == "3"
    refute Map.has_key?(changes, :building)
  end
end
