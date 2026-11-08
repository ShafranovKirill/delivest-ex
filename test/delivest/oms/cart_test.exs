defmodule Delivest.Oms.CartTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  @branch_id "00000000-0000-4000-8000-000000000001"

  alias Delivest.Oms.{Cart, CartItem, CartView, Carts}

  describe "cart schema" do
    test "accepts valid attributes" do
      attrs = %{
        session_id: "session-123",
        branch_id: Ecto.UUID.generate()
      }

      assert %Ecto.Changeset{valid?: true} = Cart.changeset(%Cart{}, attrs)
    end

    test "rejects non-positive quantity" do
      attrs = %{
        cart_id: Ecto.UUID.generate(),
        product_id: Ecto.UUID.generate(),
        quantity: 0
      }

      changeset = CartItem.changeset(%CartItem{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).quantity
    end
  end

  describe "cart context" do
    test "a delayed old cache fill cannot restore an outdated product price" do
      branch = insert(:branch)
      product = insert_branch_product(branch.id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "stale-fill", branch_id: branch.id})
      {:ok, _, _} = Carts.add_item(cart.id, product.id)
      {:ok, old_view} = Cachex.get(:cart_cache, cart.id)

      product |> Ecto.Changeset.change(price: 250) |> Repo.update!()
      Delivest.Net.Catalogs.clear_menu_cache(branch.id)
      Cachex.put(:cart_cache, cart.id, old_view)

      assert %CartView{total_amount: 250} = Carts.get_cart_by_id(cart.id)
    end

    test "rebuilds cached carts missing loyalty fields without losing items" do
      product = insert_branch_product(@branch_id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "legacy-cache", branch_id: @branch_id})
      {:ok, _, view} = Carts.add_item(cart.id, product.id)

      legacy = Map.drop(view, [:points_earned, :base_stars, :product_stars])
      Cachex.put(:cart_cache, cart.id, legacy)

      assert %CartView{} = restored = Carts.get_cart_by_id(cart.id)
      assert [%{product_id: product_id, quantity: 1}] = restored.items
      assert product_id == product.id
      assert restored.total_amount == 100
      assert restored.points_earned == 0
      assert restored.base_stars == 0
      assert restored.product_stars == 0
    end

    test "items keep the order they were added in when the quantity changes" do
      first = insert_branch_product(@branch_id, price: 100)
      second = insert_branch_product(@branch_id, price: 200)
      third = insert_branch_product(@branch_id, price: 300)

      {:ok, cart} = Carts.create_cart(%{session_id: "session-order", branch_id: @branch_id})
      for product <- [first, second, third], do: {:ok, _, _} = Carts.add_item(cart.id, product.id)

      for product <- [first, second, first, third, first] do
        {:ok, _, view} = Carts.add_item(cart.id, product.id)
        assert Enum.map(view.items, & &1.product_id) == [first.id, second.id, third.id]
      end

      {:ok, :updated, view} = Carts.remove_item(cart.id, second.id)
      assert Enum.map(view.items, & &1.product_id) == [first.id, second.id, third.id]
    end

    test "creates a cart and calculates totals" do
      product = insert_branch_product(@branch_id, price: 250)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-cart", branch_id: @branch_id})

      assert cart.total_quantity == 0
      assert cart.items == []

      assert {:ok, _item, %CartView{} = updated_cart} = Carts.add_item(cart.id, product.id, 2)
      assert updated_cart.total_quantity == 2
      assert updated_cart.total_amount == 500

      assert [%{product_id: product_id, quantity: 2, total_price: 500}] = updated_cart.items
      assert product_id == product.id
    end

    test "adds quantity to existing product instead of duplicating item" do
      product = insert_branch_product(@branch_id, price: 100)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-merge", branch_id: @branch_id})

      assert {:ok, _, %CartView{} = first} = Carts.add_item(cart.id, product.id, 1)
      assert {:ok, _, %CartView{} = second} = Carts.add_item(cart.id, product.id, 2)

      assert first.total_quantity == 1
      assert second.total_quantity == 3
      assert [%{quantity: 3, total_price: 300}] = second.items
    end

    test "decrements quantity and removes item when it reaches zero" do
      product = insert_branch_product(@branch_id, price: 80)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{session_id: "session-clear", branch_id: @branch_id})

      assert {:ok, _, %CartView{} = cart_with_item} = Carts.add_item(cart.id, product.id, 2)
      assert cart_with_item.total_quantity == 2

      assert {:ok, :updated, %CartView{} = updated_cart} = Carts.remove_item(cart.id, product.id)
      assert updated_cart.total_quantity == 1
      assert hd(updated_cart.items).quantity == 1

      assert {:ok, :deleted, %CartView{} = cleared_cart} = Carts.remove_item(cart.id, product.id)
      assert cleared_cart.items == []
      assert cleared_cart.total_quantity == 0
      assert cleared_cart.total_amount == 0
    end

    test "clear_cart removes all cart items and refreshes totals" do
      product_one = insert_branch_product(@branch_id, price: 120)
      product_two = insert_branch_product(@branch_id, price: 80)

      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "session-clear-all",
                 branch_id: @branch_id
               })

      assert {:ok, _, _} = Carts.add_item(cart.id, product_one.id, 1)
      assert {:ok, _, _} = Carts.add_item(cart.id, product_two.id, 2)

      assert {:ok, %CartView{items: items}} = Carts.clear_cart(cart.id)
      assert items == []
    end

    test "detach_cart removes session and staff attachment from the cart" do
      assert {:ok, %CartView{} = cart} =
               Carts.create_cart(%{
                 session_id: "session-detach",
                 staff_id: Ecto.UUID.generate(),
                 branch_id: @branch_id
               })

      assert {:ok, %CartView{} = detached_cart} = Carts.detach_cart(cart.id)
      assert detached_cart.session_id == nil
      assert detached_cart.staff_id == nil
    end

    test "rejects products of another branch and inactive products" do
      foreign = insert_branch_product(Ecto.UUID.generate(), price: 100)
      inactive = insert_branch_product(@branch_id, price: 100, is_active: false)

      {:ok, cart} = Carts.create_cart(%{session_id: "foreign-product", branch_id: @branch_id})

      assert {:error, :product_unavailable} = Carts.add_item(cart.id, foreign.id, 1)
      assert {:error, :product_unavailable} = Carts.add_item(cart.id, inactive.id, 1)
      assert {:error, :product_unavailable} = Carts.add_item(cart.id, "not-a-uuid", 1)
    end

    test "keeps inactive and deleted rows removable without charging for them" do
      active = insert_branch_product(@branch_id, price: 100)
      inactive = insert_branch_product(@branch_id, price: 200)
      deleted = insert_branch_product(@branch_id, price: 300)
      {:ok, cart} = Carts.create_cart(%{session_id: "unavailable-rows", branch_id: @branch_id})

      for product <- [active, inactive, deleted],
          do: {:ok, _, _} = Carts.add_item(cart.id, product.id)

      inactive |> Ecto.Changeset.change(is_active: false) |> Repo.update!()
      deleted |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      view = Carts.get_cart_by_id(cart.id, force: true)
      assert view.total_quantity == 1
      assert view.total_amount == 100
      assert Enum.count(view.items) == 3
      assert Enum.count(view.items, &Map.get(&1, :unavailable, false)) == 2

      assert %{data: %{items: json_items, total_amount: 100}} =
               DelivestWeb.Client.Cart.CartJSON.show(%{cart: view})

      assert Enum.count(json_items, & &1.unavailable) == 2
      assert Enum.any?(json_items, &(&1.unavailable_reason == :product_unavailable))
      assert Repo.aggregate(from(ci in CartItem, where: ci.cart_id == ^cart.id), :count) == 3

      assert {:ok, :deleted, remaining} = Carts.remove_item(cart.id, inactive.id, all: true)
      assert Enum.count(remaining.items) == 2
    end

    test "keeps missing and invalid-modifier rows with safe fallback metadata" do
      product = insert_branch_product(@branch_id, price: 100)
      foreign = insert_branch_product(Ecto.UUID.generate(), price: 900)
      {:ok, cart} = Carts.create_cart(%{session_id: "missing-rows", branch_id: @branch_id})
      {:ok, _, _} = Carts.add_item(cart.id, product.id)
      existing = Repo.get_by!(CartItem, cart_id: cart.id, product_id: product.id)

      existing
      |> Ecto.Changeset.change(modifiers: [%{"id" => Ecto.UUID.generate(), "quantity" => 1}])
      |> Repo.update!()

      Repo.insert!(%CartItem{cart_id: cart.id, product_id: foreign.id, quantity: 1})
      missing_id = Ecto.UUID.generate()
      Repo.insert!(%CartItem{cart_id: cart.id, product_id: missing_id, quantity: 1})

      view = Carts.get_cart_by_id(cart.id, force: true)
      assert view.total_amount == 0
      assert view.total_quantity == 0
      assert Enum.count(view.items) == 3

      assert Enum.find(view.items, &(&1.product_id == product.id)).unavailable_reason ==
               :modifier_unavailable

      for id <- [foreign.id, missing_id] do
        item = Enum.find(view.items, &(&1.product_id == id))
        assert item.unavailable_reason == :product_missing
        assert item.name == "Unavailable product"
      end

      assert Repo.aggregate(from(ci in CartItem, where: ci.cart_id == ^cart.id), :count) == 3
    end

    test "limits the quantity of a single product" do
      product = insert_branch_product(@branch_id, price: 10)
      {:ok, cart} = Carts.create_cart(%{session_id: "quantity-limit", branch_id: @branch_id})

      assert {:error, :quantity_limit_exceeded} = Carts.add_item(cart.id, product.id, 100)
      assert {:ok, _, _} = Carts.add_item(cart.id, product.id, 99)
      assert {:error, :quantity_limit_exceeded} = Carts.add_item(cart.id, product.id, 1)
    end

    test "owned_by_session? only matches the owning session" do
      {:ok, cart} = Carts.create_cart(%{session_id: "owner", branch_id: @branch_id})

      assert Carts.owned_by_session?(cart.id, "owner")
      refute Carts.owned_by_session?(cart.id, "stranger")
      refute Carts.owned_by_session?(cart.id, nil)
      refute Carts.owned_by_session?("not-a-uuid", "owner")
    end

    test "returns one cart when a session has duplicate carts for a branch" do
      {:ok, _first} = Carts.create_cart(%{session_id: "duplicated", branch_id: @branch_id})
      {:ok, _second} = Carts.create_cart(%{session_id: "duplicated", branch_id: @branch_id})

      assert %CartView{} = Carts.get_cart(session_id: "duplicated", branch_id: @branch_id)
      assert %CartView{} = Carts.get_cart(session_id: "duplicated")
    end
  end
end
