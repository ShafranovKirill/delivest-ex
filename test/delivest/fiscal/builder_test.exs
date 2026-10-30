defmodule Delivest.Fiscal.BuilderTest do
  use ExUnit.Case, async: true

  alias Delivest.Fiscal.{BranchSettings, Builder}
  alias Delivest.Oms.{Order, OrderItem}

  @settings %BranchSettings{
    mode: :own,
    inn: "5544332219",
    sno: :usn_income,
    payment_address: "https://v5.online.atol.ru",
    email: "chek@pizza.ru",
    vat: :none,
    delivery_vat: :vat20
  }

  defp order(items, delivery) do
    %Order{
      customer_phone: "+79990001122",
      delivery_amount: delivery,
      items: items
    }
  end

  defp item(attrs), do: struct(%OrderItem{quantity: 1, modifiers: []}, attrs)

  test "goods, discount and delivery add up to the payment" do
    pid = Ecto.UUID.generate()

    order =
      order(
        [
          item(product_id: pid, title: "Маргарита", price: 59_000, quantity: 2),
          item(title: "Кола", price: 15_000, gift: false),
          item(title: "Соус", price: 0, gift: true)
        ],
        20_000
      )

    receipt =
      Builder.build(order, @settings,
        payments: [%{type: :cash, sum: 140_000}],
        products: %{pid => %{vat: :vat10}},
        cashier: "Иван Петров"
      )

    assert receipt.total == 140_000
    assert Enum.sum(Enum.map(receipt.items, & &1.sum)) == 140_000

    assert %{name: "Доставка", sum: 20_000, vat: :vat20, object: :service} =
             List.last(receipt.items)

    assert [%{name: "Маргарита", vat: :vat10} | _] = receipt.items
    assert Enum.all?(receipt.items, &(&1.sum == &1.price * &1.quantity))
    assert receipt.client == %{phone: "+79990001122"}
    assert receipt.cashier == "Иван Петров"
    assert receipt.company.inn == "5544332219"
  end

  test "excise goods are marked" do
    pid = Ecto.UUID.generate()
    order = order([item(product_id: pid, title: "Лимонад", price: 10_000)], nil)

    receipt =
      Builder.build(order, @settings,
        payments: [Builder.payment(%{method: :card, amount: 10_000})],
        products: %{pid => %{excise: :sugary_drink}}
      )

    assert [%{object: :excise, vat: :none}] = receipt.items
    assert [%{type: :card, sum: 10_000}] = receipt.payments
  end
end
