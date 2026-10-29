defmodule Delivest.Promo.EngineTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Promo

  setup do
    branch = insert(:branch)
    pizza = insert_branch_product(branch.id, slug: "pizza", name: "Pizza", price: 50_000)
    cola = insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 9000)
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

    assert %{subtotal: 100_000, discount: 0, total: 100_000, applied: [], hints: [], code: nil} =
             result
  end

  test "applies a percent discount with a cap", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "then discount 20% max 150")

    assert %{subtotal: 100_000, discount: 15_000, total: 85_000, applied: [%{discount: 15_000}]} =
             price(branch, [item(pizza, 2)])
  end

  test "spreads a fixed discount across lines", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: "then discount 100 rub")

    result = price(branch, [item(pizza, 1), item(cola, 1)])

    assert result.total == 49_000
    assert result.lines |> Enum.map(& &1.total) |> Enum.sum() == 49_000
  end

  test "adds a gift line once the subtotal is reached", %{branch: branch, pizza: pizza} do
    promotion =
      insert_promotion(branch.id,
        name: "Free cola",
        rules: ~s(when subtotal >= 1000 then gift "cola")
      )

    assert %{hints: [%{name: "Free cola", reasons: [%{type: :subtotal, missing: 50_000}]}]} =
             price(branch, [item(pizza, 1)])

    result = price(branch, [item(pizza, 2)])

    assert [%{gift: false}, %{gift: true, total: 0, quantity: 1, name: "Cola"}] = result.lines
    assert [%{promotion_id: id, gifts: [%{name: "Cola", quantity: 1}]}] = result.applied
    assert id == promotion.id
    assert result.total == 100_000
  end

  test "requires selected products", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: ~s(when has "pizza" x2 then discount 10%))

    assert %{hints: [%{reasons: [%{type: :product, missing: 1}]}], total: 59_000} =
             price(branch, [item(pizza, 1), item(cola, 1)])

    assert %{total: 90_000} = price(branch, [item(pizza, 2)])
  end

  test "waits for the fulfillment type", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "when fulfillment in (pickup) then discount 10%")

    assert %{total: 50_000, hints: [%{reasons: [%{type: :fulfillment, allowed: [:pickup]}]}]} =
             price(branch, [item(pizza, 1)])

    assert %{total: 45_000} = price(branch, [item(pizza, 1)], %{fulfillment_type: "pickup"})

    assert %{total: 50_000, hints: [_]} =
             price(branch, [item(pizza, 1)], %{fulfillment_type: "delivery"})
  end

  test "respects time windows in local time", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: "when time 11:00..16:00 then discount 10%")

    noon = DateTime.new!(~D[2026-10-20], ~T[12:00:00], Delivest.LocalTime.timezone())
    night = DateTime.new!(~D[2026-10-20], ~T[23:00:00], Delivest.LocalTime.timezone())

    assert %{total: 45_000} = price(branch, [item(pizza, 1)], %{now: utc(noon)})

    assert %{total: 50_000, hints: [%{reasons: [%{type: :time}]}]} =
             price(branch, [item(pizza, 1)], %{now: utc(night)})
  end

  test "prices products with the best sale", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, combinable: true, rules: ~s(then price "pizza" 450))
    insert_promotion(branch.id, combinable: true, rules: ~s(then discount 20% on "pizza"))

    result = price(branch, [item(pizza, 2), item(cola, 1)])

    assert result.total == 40_000 * 2 + 9000
    assert [%{discount: 20_000}] = result.applied
  end

  test "does not combine non-combinable promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, priority: 10, rules: "then discount 10%")
    insert_promotion(branch.id, priority: 1, combinable: true, rules: "then discount 50 rub")

    assert %{total: 45_000, applied: [_]} = price(branch, [item(pizza, 1)])
  end

  test "combines combinable promotions percent first", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, combinable: true, rules: "then discount 50 rub")
    insert_promotion(branch.id, combinable: true, rules: "then discount 10%")

    assert %{total: 40_000, applied: [_, _]} = price(branch, [item(pizza, 1)])
  end

  test "an entered code beats automatic promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, priority: 100, rules: "then discount 10%")
    code_promo = insert_promotion(branch.id, kind: :public_code, rules: "then discount 30%")
    insert_code(code_promo, code: "SUMMER")

    result = price(branch, [item(pizza, 1)], %{code: " summer "})

    assert %{total: 35_000, code: %{status: :applied, code: "SUMMER"}} = result
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

    assert %{
             total: 50_000,
             code: %{status: :pending, reasons: [%{type: :subtotal, missing: 50_000}]}
           } =
             price(branch, [item(pizza, 1)], %{code: "BIG"})

    assert %{total: 90_000, code: %{status: :applied}} =
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

    assert %{code: %{reason: :expired}, total: 50_000} =
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

    assert %{total: 40_000, code: %{status: :applied}} =
             price(branch, [item(pizza, 1)], %{code: "MINE", client_id: owner.id})
  end

  test "asks to sign in for per-client automatic promotions", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, per_client_limit: 1, rules: "then discount 100 rub")

    assert %{total: 50_000, hints: [%{reasons: [%{type: :requires_client}]}]} =
             price(branch, [item(pizza, 1)])

    assert %{total: 40_000} = price(branch, [item(pizza, 1)], %{client_id: insert(:client).id})
  end

  test "skips effects referencing missing products", %{branch: branch, pizza: pizza} do
    insert_promotion(branch.id, rules: ~s(then gift "ghost"))

    assert %{lines: [%{gift: false}], total: 50_000} = price(branch, [item(pizza, 1)])
  end

  test "overlays unconditional sales on the menu", %{branch: branch, pizza: pizza, cola: cola} do
    insert_promotion(branch.id, rules: ~s(then price "pizza" 399))
    insert_promotion(branch.id, rules: ~s(when subtotal >= 10 then price "cola" 1))

    menu = [
      %{
        id: "c",
        name: "C",
        products: [%{id: pizza.id, price: 50_000}, %{id: cola.id, price: 9000}]
      }
    ]

    assert [%{products: [%{price: 39_900, old_price: 50_000}, %{price: 9000, old_price: nil}]}] =
             Promo.overlay_menu(menu, branch.id)
  end

  test "does not report promotions without an effect on the cart", %{branch: branch, cola: cola} do
    insert_promotion(branch.id, rules: ~s(then price "pizza" 299))

    assert %{applied: [], total: 9000} = price(branch, [item(cola, 1)])
  end

  test "lines always add up to the total on random carts", %{branch: branch} do
    products =
      for index <- 1..5,
          do: insert_branch_product(branch.id, slug: "p#{index}", price: Enum.random(1..99_999))

    insert_promotion(branch.id, combinable: true, rules: "then discount 7% max 333.33")
    insert_promotion(branch.id, combinable: true, rules: "then discount 99.99 rub")
    insert_promotion(branch.id, combinable: true, rules: ~s[then discount 13% on ("p1", "p2")])

    for _round <- 1..50 do
      items =
        products
        |> Enum.take_random(Enum.random(1..5))
        |> Enum.map(&item(&1, Enum.random(1..7)))

      result = price(branch, items)
      paid = Enum.reject(result.lines, & &1.gift)

      assert paid |> Enum.map(& &1.total) |> Enum.sum() == result.total
      assert result.subtotal - result.discount == result.total
      assert result.applied |> Enum.map(& &1.discount) |> Enum.sum() == result.discount

      for line <- paid do
        units = Delivest.Money.split_unit_price(line.total, line.quantity)
        assert units |> Enum.map(fn {unit, count} -> unit * count end) |> Enum.sum() == line.total
      end
    end
  end

  defp utc(datetime), do: DateTime.shift_zone!(datetime, "Etc/UTC")
end
