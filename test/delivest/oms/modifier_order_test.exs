defmodule Delivest.Oms.ModifierOrderTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net.{Modifier, ModifierGroup, ProductModifierGroup}
  alias Delivest.Oms.{Carts, Orders}

  setup do
    branch = insert(:branch)
    pizza = insert_branch_product(branch.id, price: 50_000)

    size = Repo.insert!(%ModifierGroup{name: "Размер", min: 1, max: 1})
    small = Repo.insert!(%Modifier{group_id: size.id, name: "25 см", price: 0, is_default: true})
    large = Repo.insert!(%Modifier{group_id: size.id, name: "35 см", price: 20_000})
    extras = Repo.insert!(%ModifierGroup{name: "Добавки", min: 0, max: 3})

    cheese =
      Repo.insert!(%Modifier{group_id: extras.id, name: "Сыр", price: 5_000, max_quantity: 2})

    Repo.insert!(%ProductModifierGroup{product_id: pizza.id, group_id: size.id, position: 0})
    Repo.insert!(%ProductModifierGroup{product_id: pizza.id, group_id: extras.id, position: 1})

    {:ok, cart} = Carts.create_cart(%{session_id: "mods", branch_id: branch.id})

    %{branch: branch, pizza: pizza, cart: cart, small: small, large: large, cheese: cheese}
  end

  test "the same product with other modifiers is another line", ctx do
    {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.pizza.id)

    {:ok, _, view} =
      Carts.add_item(ctx.cart.id, ctx.pizza.id, 1, [
        ctx.large.id,
        %{"id" => ctx.cheese.id, "quantity" => 2}
      ])

    assert [plain, rich] = Enum.sort_by(view.items, & &1.price)
    assert plain.price == 50_000
    assert [%{name: "25 см"}] = plain.modifiers
    assert rich.price == 80_000
    assert view.total_amount == 130_000

    {:ok, :deleted, view} = Carts.remove_item(ctx.cart.id, rich.key)
    assert [%{price: 50_000}] = view.items
  end

  describe "replace_item" do
    test "a single unit changes its modifiers in place", ctx do
      {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.pizza.id, 1, [ctx.small.id])
      other = insert_branch_product(ctx.branch.id, price: 10_000)
      {:ok, _, view} = Carts.add_item(ctx.cart.id, other.id)
      [pizza_line, _] = view.items

      {:ok, view} = Carts.replace_item(ctx.cart.id, pizza_line.key, [ctx.large.id])

      assert [%{product_id: pizza_id, price: 70_000}, %{product_id: other_id}] = view.items
      assert pizza_id == ctx.pizza.id
      assert other_id == other.id
    end

    test "one unit splits off a line of several", ctx do
      {:ok, _, view} = Carts.add_item(ctx.cart.id, ctx.pizza.id, 3, [ctx.small.id])
      [line] = view.items

      {:ok, view} = Carts.replace_item(ctx.cart.id, line.key, [ctx.large.id])

      assert [%{quantity: 2, price: 50_000}, %{quantity: 1, price: 70_000}] = view.items
    end

    test "it merges into a line that already has the same modifiers", ctx do
      {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.pizza.id, 1, [ctx.small.id])
      {:ok, _, view} = Carts.add_item(ctx.cart.id, ctx.pizza.id, 1, [ctx.large.id])
      [small_line, _] = view.items

      {:ok, view} = Carts.replace_item(ctx.cart.id, small_line.key, [ctx.large.id])

      assert [%{quantity: 2, price: 70_000}] = view.items
    end

    test "an unknown line is refused", ctx do
      assert {:error, :item_not_found} =
               Carts.replace_item(ctx.cart.id, ctx.pizza.id, [ctx.large.id])
    end
  end

  test "a wrong choice is refused", ctx do
    assert {:error, :modifiers_limit} =
             Carts.add_item(ctx.cart.id, ctx.pizza.id, 1, [ctx.small.id, ctx.large.id])
  end

  test "the order keeps a snapshot of the modifiers", ctx do
    {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.pizza.id, 2, [ctx.large.id, ctx.cheese.id])

    {:ok, order} =
      Orders.create_order(%{
        "cart_id" => ctx.cart.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    order = Repo.preload(order, [items: :modifiers], force: true)
    assert order.total_amount == 150_000
    assert [item] = order.items

    assert Enum.sort(Enum.map(item.modifiers, &{&1.group_name, &1.name, &1.price})) ==
             [{"Добавки", "Сыр", 5_000}, {"Размер", "35 см", 20_000}]
  end
end
