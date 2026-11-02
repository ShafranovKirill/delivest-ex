defmodule Delivest.FulfillmentTest do
  use Delivest.DataCase, async: true
  import Delivest.Factory
  alias Delivest.{Fulfillment, Oms}
  alias Delivest.Identity.Branch.{BranchInfo, FulfillmentSettings}
  alias Delivest.Oms.{Carts, Orders}

  test "old settings allow all methods, and each switch is independent" do
    assert FulfillmentSettings.enabled() == [:delivery, :pickup, :dine_in]

    assert FulfillmentSettings.enabled(%FulfillmentSettings{pickup: false}) == [
             :delivery,
             :dine_in
           ]

    assert FulfillmentSettings.enabled(%FulfillmentSettings{
             delivery: false,
             pickup: false,
             dine_in: false
           }) == []
  end

  test "new orders reject disabled methods even with a previously selected cart" do
    for type <- [:delivery, :pickup, :dine_in] do
      branch = insert(:branch)
      settings = Map.put(%FulfillmentSettings{}, type, false)
      Repo.insert!(%BranchInfo{branch_id: branch.id, fulfillment: settings})
      product = insert_branch_product(branch.id)
      {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
      {:ok, _, _} = Carts.add_item(cart.id, product.id)
      assert {:ok, _} = Oms.set_cart_fulfillment(cart.id, to_string(type))

      assert {:error, :fulfillment, :fulfillment_unavailable} =
               Orders.create_order(%{"cart_id" => cart.id, "fulfillment_type" => to_string(type)})

      assert Fulfillment.check(branch.id, type) == {:error, :fulfillment_unavailable}
    end
  end

  test "an enabled remaining method still creates an order" do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      fulfillment: %FulfillmentSettings{delivery: false, pickup: false}
    })

    product = insert_branch_product(branch.id)
    {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id)

    assert {:ok, order} =
             Orders.create_order(%{"cart_id" => cart.id, "fulfillment_type" => "dine_in"})

    assert order.fulfillment_type == :dine_in
  end
end
