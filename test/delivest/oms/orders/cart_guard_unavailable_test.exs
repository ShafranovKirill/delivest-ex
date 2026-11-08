defmodule Delivest.Oms.Orders.CartGuardUnavailableTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.{CartItem, Carts}
  alias Delivest.Oms.Orders.CartGuard
  alias Delivest.Repo

  test "checkout refuses a cart with an unavailable product even when another item remains valid" do
    branch = insert(:branch)
    available = insert_branch_product(branch.id, price: 100)
    unavailable = insert_branch_product(branch.id, price: 200)
    {:ok, cart} = Carts.create_cart(%{session_id: "guard-unavailable", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, available.id)
    {:ok, _, _} = Carts.add_item(cart.id, unavailable.id)
    unavailable |> Ecto.Changeset.change(is_active: false) |> Repo.update!()

    assert {:ok, {:error, :product_unavailable}} =
             Repo.transaction(fn -> CartGuard.acquire(cart.id, branch.id) end)

    assert Repo.get_by(CartItem, cart_id: cart.id, product_id: unavailable.id)
  end

  test "checkout refuses a cart with an invalid modifier" do
    branch = insert(:branch)
    product = insert_branch_product(branch.id, price: 100)
    {:ok, cart} = Carts.create_cart(%{session_id: "guard-modifier", branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id)
    item = Repo.get_by!(CartItem, cart_id: cart.id, product_id: product.id)

    item
    |> Ecto.Changeset.change(modifiers: [%{"id" => Ecto.UUID.generate(), "quantity" => 1}])
    |> Repo.update!()

    assert {:ok, {:error, :product_unavailable}} =
             Repo.transaction(fn -> CartGuard.acquire(cart.id, branch.id) end)
  end
end
