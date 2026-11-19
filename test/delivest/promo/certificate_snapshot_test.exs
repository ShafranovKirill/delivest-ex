defmodule Delivest.Promo.CertificateSnapshotTest do
  use Delivest.DataCase, async: true

  alias Delivest.Oms.Order
  alias Delivest.Oms.Orders.Assembler
  alias Delivest.Promo.{Basket, Compiled, Line, PromoCode, Promotion, Result, Strategy}

  test "applied order keeps a copy of the linked certificate and its export rule" do
    promotion_id = Ecto.UUID.generate()

    certificate = %{
      "provider" => "frontpad",
      "code" => "CERT20",
      "type" => "amount",
      "amount" => 2_000
    }

    promotion = %Promotion{
      id: promotion_id,
      branch_id: Ecto.UUID.generate(),
      kind: :public_code,
      name: "Promo",
      crm_certificate: certificate
    }

    code = %PromoCode{id: Ecto.UUID.generate(), promotion_id: promotion_id, code: "SITE20"}

    compiled = %Compiled{
      promotion: promotion,
      strategy: %Strategy{effects: [{:amount, 2_000, :cart}]}
    }

    basket = %Basket{
      lines: [%Line{base_price: 10_000, total: 8_000, quantity: 1}],
      discounts: %{promotion_id => 2_000}
    }

    pricing = Result.build(basket, [compiled], code, [], nil)

    changeset =
      Assembler.changeset(
        %Order{},
        %{"cart_id" => Ecto.UUID.generate()},
        %{
          cart: %{id: Ecto.UUID.generate(), branch_id: promotion.branch_id},
          lines: %{items: [], total_amount: 8_000},
          client_id: nil,
          pricing: pricing
        }
      )

    [applied_changeset] = Ecto.Changeset.get_embed(changeset, :promotions)
    applied = Ecto.Changeset.apply_changes(applied_changeset)
    assert applied.crm_certificate == certificate
    assert applied.certificate_export_mode == "cart_amount"

    loaded =
      applied
      |> Ecto.embedded_dump(:json)
      |> then(&Ecto.embedded_load(Delivest.Oms.Order.AppliedPromotion, &1, :json))

    assert loaded.crm_certificate == certificate
    assert loaded.certificate_export_mode == "cart_amount"
  end
end
