defmodule Delivest.Integrations.Frontpad.CertificateDeliveryTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.{Order, OrderItem}
  alias Delivest.Oms.Order.AppliedPromotion

  defp order do
    branch = insert(:branch)
    product = insert_branch_product(branch.id, external_id: "a1", price: 100)

    certificate = %{
      "provider" => "frontpad",
      "code" => "CERT20",
      "type" => "amount",
      "amount" => 2_000
    }

    %Order{
      branch_id: branch.id,
      items: [
        %OrderItem{
          product_id: product.id,
          quantity: 1,
          base_price: 10_000,
          price: 8_000,
          modifiers: []
        }
      ],
      subtotal_amount: 10_000,
      discount_amount: 2_000,
      total_amount: 8_000,
      promotions: [
        %AppliedPromotion{
          promotion_id: Ecto.UUID.generate(),
          promo_code_id: Ecto.UUID.generate(),
          name: "Promo",
          code: "SITE20",
          discount: 2_000,
          crm_certificate: certificate,
          certificate_export_mode: "cart_amount"
        }
      ]
    }
  end

  defp stub(current) do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {conn.query_string, URI.decode_query(body)})

      case conn.query_string do
        "get_certificate" ->
          case current do
            :unavailable -> Req.Test.transport_error(conn, :timeout)
            response -> Req.Test.json(conn, response)
          end

        "new_order" ->
          Req.Test.json(conn, %{"result" => "success", "order_id" => "555"})
      end
    end)
  end

  test "rechecks an unchanged certificate before sending it without a second discount" do
    stub(%{"result" => "success", "amount" => "20"})

    assert {:ok, %{external_id: "555"}} =
             Frontpad.deliver_order(order(), %Frontpad.Settings{api_key: "secret"})

    assert_receive {"get_certificate", %{"certificate" => "CERT20", "secret" => "secret"}}
    assert_receive {"new_order", params}
    assert params["certificate"] == "CERT20"
    refute Map.has_key?(params, "sale_amount")
  end

  test "sends the website price when the certificate changed after it was attached" do
    stub(%{"result" => "success", "amount" => "10"})

    assert {:ok, %{alert: alert}} =
             Frontpad.deliver_order(order(), %Frontpad.Settings{api_key: "secret"})

    assert_receive {"get_certificate", _}
    assert_receive {"new_order", params}
    refute Map.has_key?(params, "certificate")
    assert params["sale_amount"] == "20"
    assert String.contains?(params["descr"], "CERT20")
    assert String.contains?(alert, "изменился")
  end

  test "sends the website price when the fresh check is unavailable" do
    stub(:unavailable)

    assert {:ok, %{alert: alert}} =
             Frontpad.deliver_order(order(), %Frontpad.Settings{api_key: "secret"})

    assert_receive {"get_certificate", _}
    assert_receive {"new_order", params}
    refute Map.has_key?(params, "certificate")
    assert params["sale_amount"] == "20"
    assert String.contains?(alert, "не удалось перепроверить")
  end

  test "keeps the website gift when its Frontpad certificate was changed" do
    checked = order()
    gift = insert_branch_product(checked.branch_id, external_id: "gift", price: 50)
    [paid] = checked.items
    [promotion] = checked.promotions

    checked = %{
      checked
      | items: [
          %{paid | price: 10_000},
          %OrderItem{
            product_id: gift.id,
            quantity: 1,
            base_price: 5_000,
            price: 0,
            gift: true,
            modifiers: []
          }
        ],
        discount_amount: 0,
        total_amount: 10_000,
        promotions: [
          %{
            promotion
            | discount: 0,
              crm_certificate: %{
                "provider" => "frontpad",
                "code" => "GIFT01",
                "type" => "product",
                "product_id" => "gift",
                "name" => "Gift",
                "price" => 0
              },
              certificate_export_mode: "single_gift"
          }
        ]
    }

    stub(%{"result" => "success", "product_id" => "gift", "name" => "Gift", "price" => "5"})

    assert {:ok, %{alert: alert}} =
             Frontpad.deliver_order(checked, %Frontpad.Settings{api_key: "secret"})

    assert_receive {"get_certificate", _}
    assert_receive {"new_order", params}
    refute Map.has_key?(params, "certificate")
    assert params["product[1]"] == "gift"
    assert params["sale_amount"] == "50"
    assert String.contains?(alert, "изменился")
  end

  test "sends one request for an order with no linked certificate" do
    stub(%{"result" => "success", "amount" => "20"})
    checked = %{order() | promotions: []}

    assert {:ok, %{external_id: "555"}} =
             Frontpad.deliver_order(checked, %Frontpad.Settings{api_key: "secret"})

    assert_receive {"new_order", params}
    refute Map.has_key?(params, "certificate")
    refute_receive {"get_certificate", _}
  end
end
