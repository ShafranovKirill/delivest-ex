defmodule Delivest.Integrations.Frontpad.FrontpadViewTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Frontpad.{FrontpadView, Settings}
  alias Delivest.Oms.{Order, OrderItem}

  test "maps cook_by to Frontpad datetime using the required format" do
    order = %Order{
      cook_by: ~N[2026-10-15 15:30:00],
      items: [%OrderItem{product_id: "product-1", quantity: 2}]
    }

    settings = %Settings{api_key: "secret"}
    products_map = %{"product-1" => %{external_id: "frontpad-product-1"}}

    assert {:ok, view} = FrontpadView.build(order, settings, products_map)

    assert {"datetime", "2026-10-15 15:30:00"} in FrontpadView.to_form_params(view)
  end

  test "omits Frontpad datetime when cook_by is empty" do
    order = %Order{items: []}
    settings = %Settings{api_key: "secret"}

    assert {:ok, view} = FrontpadView.build(order, settings, %{})

    refute Enum.any?(FrontpadView.to_form_params(view), fn {key, _value} -> key == "datetime" end)
  end

  test "takes phone and name from the linked client once the order is reloaded" do
    order = %Order{
      items: [],
      client: %Delivest.Identity.Client{phone: "+79991234567", name: "Иван"}
    }

    settings = %Settings{api_key: "secret"}

    assert {:ok, view} = FrontpadView.build(order, settings, %{})

    params = FrontpadView.to_form_params(view)
    assert {"phone", "+79991234567"} in params
    assert {"name", "Иван"} in params
  end

  test "sends the Frontpad branch as affiliate" do
    settings = %Settings{api_key: "secret", affiliate: "7"}

    assert {:ok, view} = FrontpadView.build(%Order{items: []}, settings, %{})
    assert {"affiliate", "7"} in FrontpadView.to_form_params(view)
  end

  test "requires an api key" do
    assert {:error, :missing_api_key} = FrontpadView.build(%Order{items: []}, %Settings{}, %{})
  end
end
