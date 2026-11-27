defmodule Delivest.Net.CombosTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net.{Combos, Modifiers}
  alias Delivest.Oms.{Carts, Orders}
  alias Delivest.{Relations, Repo}

  test "editing a combo keeps the placed order's component snapshot" do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    category = insert(:category)
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    component = insert_branch_product(branch.id, name: "Burger", category: category)
    combo = insert_branch_product(branch.id, name: "Lunch", is_combo: true, price: 40_000)
    staff = Repo.preload(staff, [:role, :branches])

    config = [
      %{
        "name" => "Main",
        "required" => "true",
        "options" => [%{"component_product_id" => component.id, "price" => "25"}]
      }
    ]

    assert {:ok, _} = Combos.replace(staff, combo, branch.id, config)
    [group] = Map.fetch!(Modifiers.for_products([combo.id]), combo.id)
    [choice] = group.modifiers

    {:ok, cart} = Carts.create_cart(%{session_id: "combo-snapshot", branch_id: branch.id})
    assert {:ok, _, _} = Carts.add_item(cart.id, combo.id, 1, [choice.id])

    assert {:ok, order} =
             Orders.create_order(%{
               "cart_id" => cart.id,
               "branch_id" => branch.id,
               "fulfillment_type" => "pickup",
               "payment_method" => "cash"
             })

    assert {:ok, _} =
             Combos.replace(staff, combo, branch.id, [
               %{
                 "name" => "Main",
                 "required" => "true",
                 "options" => [%{"component_product_id" => component.id, "price" => "30"}]
               }
             ])

    order = Repo.preload(order, [items: :modifiers], force: true)
    assert [item] = order.items
    assert [%{group_name: "Main", name: "Burger", price: 2500}] = item.modifiers
  end
end
