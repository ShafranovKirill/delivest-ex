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

  describe "discounts" do
    setup do
      order = %Order{
        items: [
          %OrderItem{product_id: "p1", quantity: 2, price: 80, base_price: 100},
          %OrderItem{product_id: "p2", quantity: 1, price: 50, base_price: 50},
          %OrderItem{product_id: "p3", quantity: 1, price: 0, base_price: 90, gift: true}
        ]
      }

      products = %{
        "p1" => %{external_id: "a1"},
        "p2" => %{external_id: "a2"},
        "p3" => %{external_id: "a3"}
      }

      %{order: order, products: products}
    end

    test "forces discounted prices when price override is enabled", ctx do
      settings = %Settings{api_key: "secret", price_override: true}

      assert {:ok, view} = FrontpadView.build(ctx.order, settings, ctx.products)
      params = FrontpadView.to_form_params(view)

      assert {"product_price[0]", "80"} in params
      refute Enum.any?(params, fn {key, _} -> key == "product_price[1]" end)
      assert {"product_price[2]", "0"} in params
      refute Enum.any?(params, fn {key, _} -> key == "sale_amount" end)
    end

    test "sends the whole discount as sale_amount otherwise", ctx do
      assert {:ok, view} =
               FrontpadView.build(ctx.order, %Settings{api_key: "secret"}, ctx.products)

      params = FrontpadView.to_form_params(view)

      assert {"sale_amount", "130"} in params
      refute Enum.any?(params, fn {key, _} -> String.starts_with?(key, "product_price") end)
    end
  end

  test "requires an api key" do
    assert {:error, :missing_api_key} = FrontpadView.build(%Order{items: []}, %Settings{}, %{})
  end
end
