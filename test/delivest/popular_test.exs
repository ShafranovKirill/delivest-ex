defmodule Delivest.PopularTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.{Popular, Repo}

  test "manual mode returns the picked products in order" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    first = insert_branch_product(branch.id, name: "Первый")
    second = insert_branch_product(branch.id, name: "Второй")

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "manual"})
    {:ok, _} = Popular.add_product(admin, branch.id, first.id)
    {:ok, _} = Popular.add_product(admin, branch.id, second.id)

    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [first.id, second.id]

    {:ok, _} = Popular.reorder(admin, branch.id, [second.id, first.id])
    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [second.id, first.id]

    {:ok, _} = Popular.remove_product(admin, branch.id, second.id)
    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [first.id]
  end

  test "off mode hides the popular list but keeps the picked products" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    product = insert_branch_product(branch.id)

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "manual"})
    {:ok, _} = Popular.add_product(admin, branch.id, product.id)

    assert [%{id: id}] = Popular.list_products(branch.id)
    assert id == product.id

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "off"})
    assert Popular.list_products(branch.id) == []
    assert Popular.list_product_ids(branch.id) == [product.id]
  end

  test "auto mode picks the best-selling products of the branch" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    product = insert_branch_product(branch.id)

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "auto", "auto_limit" => 3})

    assert Popular.list_products(branch.id) == []

    cart = Repo.insert!(%Delivest.Oms.Cart{branch_id: branch.id, fulfillment_type: "pickup"})

    order =
      Repo.insert!(%Delivest.Oms.Order{
        number: "1",
        daily_number: 1,
        business_date: Date.utc_today(),
        branch_id: branch.id,
        cart_id: cart.id,
        status: :completed,
        fulfillment_type: :pickup,
        payment_method: :cash
      })

    Repo.insert!(%Delivest.Oms.OrderItem{
      order_id: order.id,
      product_id: product.id,
      title: product.name,
      price: 100,
      quantity: 5
    })

    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [product.id]
  end

  test "editing is forbidden without products.update" do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))

    assert {:error, :forbidden} =
             Popular.update_settings(staff, branch.id, %{"mode" => "auto"})
  end
end
