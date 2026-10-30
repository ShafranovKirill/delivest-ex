defmodule Delivest.Integrations.Frontpad.OrderPayloadTest do
  use Delivest.DataCase, async: true

  alias Delivest.Integrations.Frontpad.{OrderPayload, Settings}
  alias Delivest.Oms.{Order, OrderItem}

  test "maps cook_by to Frontpad datetime using the required format" do
    order = %Order{
      cook_by: ~U[2026-10-15 12:30:00Z],
      items: [%OrderItem{product_id: "product-1", quantity: 2}]
    }

    settings = %Settings{api_key: "secret"}
    products_map = %{"product-1" => %{external_id: "frontpad-product-1"}}

    assert {:ok, view} = OrderPayload.build(order, settings, products_map)

    assert {"datetime", "2026-10-15 15:30:00"} in OrderPayload.to_form_params(view)
  end

  test "omits Frontpad datetime when cook_by is empty" do
    order = %Order{items: []}
    settings = %Settings{api_key: "secret"}

    assert {:ok, view} = OrderPayload.build(order, settings, %{})

    refute Enum.any?(OrderPayload.to_form_params(view), fn {key, _value} -> key == "datetime" end)
  end

  test "takes phone, name and persons from the order snapshot" do
    order = %Order{
      items: [],
      customer_phone: "+79991234567",
      customer_phone_ext: "123",
      customer_name: "Иван",
      persons: 3
    }

    settings = %Settings{api_key: "secret"}

    assert {:ok, view} = OrderPayload.build(order, settings, %{})

    params = OrderPayload.to_form_params(view)
    assert {"phone", "+79991234567"} in params
    assert {"name", "Иван"} in params
    assert {"person", "3"} in params
    assert {"descr", "Phone extension 123"} in params
  end

  test "the order number goes first in the description" do
    order = %Order{items: [], number: "A123", comment: "Без лука"}

    assert {:ok, view} = OrderPayload.build(order, %Settings{api_key: "secret"}, %{})
    assert {"descr", "№A123. Без лука"} in OrderPayload.to_form_params(view)
  end

  test "delivery goes as the delivery product line or into the description" do
    order = %Order{items: [], delivery_amount: 15_000, comment: "Без лука"}

    assert {:ok, view} =
             OrderPayload.build(order, %Settings{api_key: "secret", delivery_article: "900"}, %{})

    params = OrderPayload.to_form_params(view)
    assert {"product[0]", "900"} in params
    assert {"product_kol[0]", "1"} in params
    assert {"product_price[0]", "150"} in params
    assert {"descr", "Без лука"} in params

    assert {:ok, view} = OrderPayload.build(order, %Settings{api_key: "secret"}, %{})
    params = OrderPayload.to_form_params(view)
    refute Enum.any?(params, fn {key, _value} -> key == "product[0]" end)
    assert {"descr", "Delivery 150 ₽. Без лука"} in params
  end

  test "sends the Frontpad branch as affiliate" do
    settings = %Settings{api_key: "secret", affiliate: "7"}

    assert {:ok, view} = OrderPayload.build(%Order{items: []}, settings, %{})
    assert {"affiliate", "7"} in OrderPayload.to_form_params(view)
  end

  test "maps the unified address and puts courier notes into the description" do
    order = %Order{
      items: [],
      comment: "Без лука",
      address: %Delivest.Oms.Order.Address{
        street: "ул Ленина",
        house: "10 к 2",
        entrance: "п.3",
        floor: "12",
        apartment: "45",
        intercom: "45В",
        comment: "Вход со двора"
      }
    }

    assert {:ok, payload} = OrderPayload.build(order, %Settings{api_key: "secret"}, %{})
    params = OrderPayload.to_form_params(payload)

    assert {"street", "ул Ленина"} in params
    assert {"home", "10 к 2"} in params
    assert {"pod", "3"} in params
    assert {"et", "12"} in params
    assert {"apart", "45"} in params
    assert {"descr", "Intercom 45В. Вход со двора. Без лука"} in params
  end

  describe "discounts" do
    setup do
      order = %Order{
        items: [
          %OrderItem{product_id: "p1", quantity: 2, price: 7950, base_price: 10_000},
          %OrderItem{product_id: "p2", quantity: 1, price: 5000, base_price: 5000},
          %OrderItem{product_id: "p3", quantity: 1, price: 0, base_price: 9000, gift: true}
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

      assert {:ok, view} = OrderPayload.build(ctx.order, settings, ctx.products)
      params = OrderPayload.to_form_params(view)

      assert {"product_price[0]", "79.5"} in params
      refute Enum.any?(params, fn {key, _} -> key == "product_price[1]" end)
      assert {"product_price[2]", "0"} in params
      refute Enum.any?(params, fn {key, _} -> key == "sale_amount" end)
    end

    test "sends the whole discount as sale_amount otherwise", ctx do
      assert {:ok, view} =
               OrderPayload.build(ctx.order, %Settings{api_key: "secret"}, ctx.products)

      params = OrderPayload.to_form_params(view)

      assert {"sale_amount", "131"} in params
      refute Enum.any?(params, fn {key, _} -> String.starts_with?(key, "product_price") end)
    end
  end

  test "requires an api key" do
    assert {:error, :missing_api_key} = OrderPayload.build(%Order{items: []}, %Settings{}, %{})
  end

  describe "payment and order marks" do
    alias Delivest.Integrations.Frontpad.{PaymentCodes, StatusCodes, TagCodes}

    defp params(order, settings) do
      {:ok, payload} = OrderPayload.build(%{order | items: []}, settings, %{})
      OrderPayload.to_form_params(payload)
    end

    test "default payment codes are cash 1 and card 2, online falls back to card" do
      settings = %Settings{api_key: "secret"}

      assert {"pay", "1"} in params(%Order{payment_method: :cash}, settings)
      assert {"pay", "2"} in params(%Order{payment_method: :card_offline}, settings)
      assert {"pay", "2"} in params(%Order{payment_method: :online}, settings)
    end

    test "configured payment codes are sent" do
      settings = %Settings{
        api_key: "secret",
        payments: %PaymentCodes{cash: "1", card_offline: "", online: "317"}
      }

      assert {"pay", "317"} in params(%Order{payment_method: :online}, settings)
      assert {"pay", "2"} in params(%Order{payment_method: :card_offline}, settings)
    end

    test "the source and online payment become order marks" do
      settings = %Settings{
        api_key: "secret",
        tags: %TagCodes{app: "1500", yandex_eda: "1363", paid_online: "1291"}
      }

      params = params(%Order{source: "yandex_eda", payment_method: :online}, settings)
      assert {"tags[0]", "1363"} in params
      assert {"tags[1]", "1291"} in params

      params = params(%Order{source: "staff", payment_method: :cash}, settings)
      refute Enum.any?(params, fn {key, _value} -> String.starts_with?(key, "tags") end)
    end

    test "no more than five status hooks, the least needed is dropped" do
      codes = %StatusCodes{
        accepted: "1",
        preparing: "2",
        ready: "3",
        delivering: "4",
        completed: "5",
        cancelled: "6"
      }

      assert Enum.sort(StatusCodes.codes(codes)) == ["2", "3", "4", "5", "6"]
    end

    test "codes are digits only" do
      refute PaymentCodes.changeset(%PaymentCodes{}, %{"online" => "abc"}).valid?
      refute TagCodes.changeset(%TagCodes{}, %{"app" => "1 2"}).valid?
      assert TagCodes.changeset(%TagCodes{}, %{"app" => "1500", "staff" => ""}).valid?
    end
  end

  test "a modifier with an article goes as a product tied to its parent" do
    order = %Order{
      items: [
        %OrderItem{
          product_id: "pizza",
          quantity: 2,
          modifiers: [
            %Delivest.Oms.OrderItemModifier{
              modifier_id: "cheese",
              name: "Сыр",
              price: 5_000,
              quantity: 1
            },
            %Delivest.Oms.OrderItemModifier{
              modifier_id: "thin",
              name: "Тонкое",
              price: 0,
              quantity: 1
            }
          ]
        }
      ]
    }

    products = %{"pizza" => %{external_id: "10"}, "cheese" => %{external_id: "77"}}
    assert {:ok, view} = OrderPayload.build(order, %Settings{api_key: "secret"}, products)
    params = OrderPayload.to_form_params(view)

    assert {"product[0]", "10"} in params
    assert {"product[1]", "77"} in params
    assert {"product_kol[1]", "2"} in params
    assert {"product_mod[1]", "0"} in params

    paid_without_article =
      put_in(order.items, [
        %{
          hd(order.items)
          | modifiers: [
              %Delivest.Oms.OrderItemModifier{
                modifier_id: "bacon",
                name: "Бекон",
                price: 7_000,
                quantity: 1
              }
            ]
        }
      ])

    assert {:error, {:missing_external_id, "bacon"}} =
             OrderPayload.build(paid_without_article, %Settings{api_key: "secret"}, products)
  end
end
