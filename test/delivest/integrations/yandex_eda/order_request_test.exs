defmodule Delivest.Integrations.YandexEda.OrderRequestTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.YandexEda.{OrderItems, OrderRequest}

  @params %{
    "discriminator" => "pickup",
    "eatsId" => "260427-100",
    "restaurantId" => "branch",
    "platform" => "DC",
    "comment" => "  Без лука ",
    "persons" => 2,
    "items" => [%{"id" => "soup", "name" => "Суп", "quantity" => 2, "price" => 199.9}],
    "paymentInfo" => %{"paymentType" => "CASH", "itemsCost" => 380.5, "change" => 1000},
    "deliveryInfo" => %{
      "clientName" => "Анна",
      "phoneNumber" => "+79990001122",
      "realPhoneNumber" => "+79990003344",
      "pickupCode" => "1234",
      "clientArrivementDate" => "2026-10-27T12:30:00.870000+03:00"
    }
  }

  test "a pickup order is parsed" do
    assert {:ok, %OrderRequest{} = request} = OrderRequest.parse(@params)

    assert request.eats_id == "260427-100"
    assert request.platform == "DC"
    assert request.comment == "Без лука"
    assert request.phone == "+79990003344"
    assert request.paid == false
    assert request.items_cost == 380
    assert request.change == 1000
    assert request.address == nil
    assert request.target_at == ~U[2026-10-27 09:30:00Z]
    assert [%{product_id: "soup", quantity: 2, total: 398}] = request.items
  end

  test "a marketplace order needs the address and its coordinates" do
    params =
      Map.merge(@params, %{
        "discriminator" => "marketplace",
        "deliveryInfo" => %{
          "deliveryDate" => "2026-10-27T13:00:00+03:00",
          "deliveryAddress" => %{"full" => "Москва", "latitude" => "55.75", "longitude" => 37.6}
        }
      })

    assert {:ok, %OrderRequest{address: %{full: "Москва", latitude: 55.75, longitude: 37.6}}} =
             OrderRequest.parse(params)

    params = put_in(params, ["deliveryInfo", "deliveryAddress", "latitude"], "north")
    assert {:error, "deliveryInfo.deliveryAddress is required"} = OrderRequest.parse(params)
  end

  test "the target time is taken from the field of the delivery scheme" do
    params = Map.put(@params, "discriminator", "yandex")
    assert {:error, "deliveryInfo.courierArrivementDate is required"} = OrderRequest.parse(params)
  end

  test "broken requests are rejected" do
    assert {:error, _} = OrderRequest.parse(Map.put(@params, "discriminator", "drone"))
    assert {:error, "eatsId is required"} = OrderRequest.parse(Map.delete(@params, "eatsId"))
    assert {:error, "items are required"} = OrderRequest.parse(Map.put(@params, "items", []))

    assert {:error, _} =
             OrderRequest.parse(put_in(@params, ["paymentInfo", "paymentType"], "CRYPTO"))

    assert {:error, "paymentInfo.itemsCost is required"} =
             OrderRequest.parse(put_in(@params, ["paymentInfo", "itemsCost"], nil))
  end

  test "items are rounded and merged by product" do
    assert {:ok, [soup, tea]} =
             OrderItems.parse([
               %{"id" => "soup", "quantity" => 1.5, "price" => 99.99},
               %{"id" => "tea", "quantity" => 1, "price" => 50},
               %{"id" => "soup", "quantity" => 1, "price" => 99.99}
             ])

    assert %{product_id: "soup", name: "soup", quantity: 3, total: 297} = soup
    assert %{product_id: "tea", quantity: 1, total: 50} = tea

    assert {:error, _} = OrderItems.parse([%{"id" => "soup", "quantity" => 0, "price" => 1}])
  end
end
