defmodule Delivest.Promo.EngineTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Promo

  setup do
    branch = insert(:branch)
    pizza = insert_branch_product(branch.id, slug: "pizza", name: "Pizza", price: 500)
    cola = insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 90)
    %{branch: branch, pizza: pizza, cola: cola}
  end

  defp item(product, quantity),
    do: %{
      product_id: product.id,
      name: product.name,
      image_url: nil,
      price: product.price,
      quantity: quantity
    }

  defp price(branch, items, context \\ %{}),
    do: Promo.price(items, Map.put(context, :branch_id, branch.id))

  test "returns plain totals without promotions", %{branch: branch, pizza: pizza} do
    result = price(branch, [item(pizza, 2)])

    assert %{subtotal: 1000, discount: 0, total: 1000, applied: [], hints: [], code: nil} = result
  end

  test "applies a percent discount with a cap", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "then discount 20% max 150")

    assert %{subtotal: 1000, discount: 150, total: 850, applied: [%{discount: 150}]} =
             price(branch, [item(pizza, 2)])
  end

  test "spreads a fixed discount across lines", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: "then discount 100 rub")

    result = price(branch, [item(pizza, 1), item(cola, 1)])

    assert result.total == 490
    assert result.lines |> Enum.map(& &1.total) |> Enum.sum() == 490
  end

  test "adds a gift line once the subtotal is reached", %{branch: branch, pizza: pizza} do
    promotion =
      insert_promotion(branch.id,
        name: "Free cola",
        rules: ~s(when subtotal >= 1000 then gift "cola")
      )

    assert %{hints: [%{name: "Free cola", reasons: [%{type: :subtotal, missing: 500}]}]} =
             price(branch, [item(pizza, 1)])

    result = price(branch, [item(pizza, 2)])

    assert [%{gift: false}, %{gift: true, total: 0, quantity: 1, name: "Cola"}] = result.lines
    assert [%{promotion_id: id, gifts: [%{name: "Cola", quantity: 1}]}] = result.applied
    assert id == promotion.id
    assert result.total == 1000
  end

  test "requires selected products", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: ~s(when has "pizza" x2 then discount 10%))

    assert %{hints: [%{reasons: [%{type: :product, missing: 1}]}], total: 590} =
             price(branch, [item(pizza, 1), item(cola, 1)])

    assert %{total: 900} = price(branch, [item(pizza, 2)])
  end

  test "waits for the fulfillment type", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "when fulfillment in (pickup) then discount 10%")

    assert %{total: 500, hints: [%{reasons: [%{type: :fulfillment, allowed: [:pickup]}]}]} =
             price(branch, [item(pizza, 1)])

    assert %{total: 450} = price(branch, [item(pizza, 1)], %{fulfillment_type: "pickup"})

    assert %{total: 500, hints: [_]} =
             price(branch, [item(pizza, 1)], %{fulfillment_type: "delivery"})
  end

  test "respects time windows in local time", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "when time 11:00..16:00 then discount 10%")

    noon = DateTime.new!(~D[2026-10-20], ~T[12:00:00], Delivest.LocalTime.timezone())
    night = DateTime.new!(~D[2026-10-20], ~T[23:00:00], Delivest.LocalTime.timezone())

    assert %{total: 450} = price(branch, [item(pizza, 1)], %{now: utc(noon)})

    assert %{total: 500, hints: [%{reasons: [%{type: :time}]}]} =
             price(branch, [item(pizza, 1)], %{now: utc(night)})
  end

  test "prices products with the best sale", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, combinable: true, rules: ~s(then price "pizza" 450))
    insert_promotion(branch.id, combinable: true, rules: ~s(then discount 20% on "pizza"))

    result = price(branch, [item(pizza, 2), item(cola, 1)])

    assert result.total == 400 * 2 + 90
    assert [%{discount: 0}, %{discount: 200}] = Enum.sort_by(result.applied, & &1.discount)
  end

  test "does not combine non-combinable promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, priority: 10, rules: "then discount 10%")
    insert_promotion(branch.id, priority: 1, combinable: true, rules: "then discount 50 rub")

    assert %{total: 450, applied: [_]} = price(branch, [item(pizza, 1)])
  end

  test "combines combinable promotions percent first", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, combinable: true, rules: "then discount 50 rub")
    insert_promotion(branch.id, combinable: true, rules: "then discount 10%")

    assert %{total: 400, applied: [_, _]} = price(branch, [item(pizza, 1)])
  end

  test "an entered code beats automatic promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, priority: 100, rules: "then discount 10%")
    code_promo = insert_promotion(branch.id, kind: :public_code, rules: "then discount 30%")
    insert_code(code_promo, code: "SUMMER")

    result = price(branch, [item(pizza, 1)], %{code: " summer "})

    assert %{total: 350, code: %{status: :applied, code: "SUMMER"}} = result
    assert [%{promotion_id: id, code: "SUMMER"}] = result.applied
    assert id == code_promo.id
  end

  test "keeps a code pending until its conditions are met", %{branch: branch, pizza: pizza} do
    promo =
      insert_promotion(branch.id,
        kind: :public_code,
        rules: "when subtotal >= 1000 then discount 100 rub"
      )

    insert_code(promo, code: "BIG")

    assert %{total: 500, code: %{status: :pending, reasons: [%{type: :subtotal, missing: 500}]}} =
             price(branch, [item(pizza, 1)], %{code: "BIG"})

    assert %{total: 900, code: %{status: :applied}} =
             price(branch, [item(pizza, 2)], %{code: "BIG"})
  end

  test "rejects unknown, disabled, expired and future codes", %{branch: branch, pizza: pizza} do
    assert %{code: %{status: :rejected, reason: :not_found}} =
             price(branch, [item(pizza, 1)], %{code: "NOPE"})

    disabled = insert_promotion(branch.id, kind: :public_code, enabled: false)
    insert_code(disabled, code: "OFF")
    assert %{code: %{reason: :inactive}} = price(branch, [item(pizza, 1)], %{code: "OFF"})

    expired =
      insert_promotion(branch.id,
        kind: :public_code,
        ends_at: DateTime.add(DateTime.utc_now(:second), -60)
      )

    insert_code(expired, code: "OLD")

    assert %{code: %{reason: :expired}, total: 500} =
             price(branch, [item(pizza, 1)], %{code: "OLD"})

    future =
      insert_promotion(branch.id,
        kind: :public_code,
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600)
      )

    insert_code(future, code: "SOON")
    assert %{code: %{reason: :not_started}} = price(branch, [item(pizza, 1)], %{code: "SOON"})
  end

  test "binds personal codes to their owner", %{branch: branch, pizza: pizza} do
    owner = insert(:client)
    stranger = insert(:client)
    promo = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 100 rub")
    insert_code(promo, code: "MINE", client_id: owner.id)

    assert %{code: %{reason: :requires_client}} = price(branch, [item(pizza, 1)], %{code: "MINE"})

    assert %{code: %{reason: :not_owner}} =
             price(branch, [item(pizza, 1)], %{code: "MINE", client_id: stranger.id})

    assert %{total: 400, code: %{status: :applied}} =
             price(branch, [item(pizza, 1)], %{code: "MINE", client_id: owner.id})
  end

  test "asks to sign in for per-client automatic promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, per_client_limit: 1, rules: "then discount 100 rub")

    assert %{total: 500, hints: [%{reasons: [%{type: :requires_client}]}]} =
             price(branch, [item(pizza, 1)])

    assert %{total: 400} = price(branch, [item(pizza, 1)], %{client_id: insert(:client).id})
  end

  test "skips effects referencing missing products", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: ~s(then gift "ghost"))

    assert %{lines: [%{gift: false}], total: 500} = price(branch, [item(pizza, 1)])
  end

  test "overlays unconditional sales on the menu", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: ~s(then price "pizza" 399))
    insert_promotion(branch.id, rules: ~s(when subtotal >= 10 then price "cola" 1))

    menu = [
      %{id: "c", name: "C", products: [%{id: pizza.id, price: 500}, %{id: cola.id, price: 90}]}
    ]

    assert [%{products: [%{price: 399, old_price: 500}, %{price: 90, old_price: nil}]}] =
             Promo.overlay_menu(menu, branch.id)
  end

  defp utc(datetime), do: DateTime.shift_zone!(datetime, "Etc/UTC")
end
