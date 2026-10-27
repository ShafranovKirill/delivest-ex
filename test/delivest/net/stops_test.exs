defmodule Delivest.Net.StopsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net.{ProductStop, StopPeriod, Stops}
  alias Delivest.Oms
  alias Delivest.Oms.Carts

  setup do
    role = insert(:role, permissions: ["products.update"])
    branch = insert(:branch, is_active: true)
    %{staff: insert(:staff, role: role), branch: branch}
  end

  describe "manual stops" do
    test "stop until resumed and resume", %{staff: staff, branch: branch} do
      product = insert_branch_product(branch.id)

      assert {:ok, %ProductStop{until: nil}} =
               Stops.stop(staff, branch.id, product, :until_resumed)

      assert Stops.stopped?(branch.id, product.id)

      assert {:ok, _} = Stops.resume(staff, branch.id, product)
      refute Stops.stopped?(branch.id, product.id)
    end

    test "a stop for today expires at the start of the next business day",
         %{staff: staff, branch: branch} do
      product = insert_branch_product(branch.id)
      {:ok, stop} = Stops.stop(staff, branch.id, product, :today)

      assert Stops.stopped?(branch.id, product.id)
      refute Stops.stopped?(branch.id, product.id, DateTime.add(stop.until, 1))
    end

    test "requires the products.update permission", %{branch: branch} do
      staff = insert(:staff, role: insert(:role, permissions: []))
      product = insert_branch_product(branch.id)

      assert {:error, :forbidden} = Stops.stop(staff, branch.id, product, :today)
    end
  end

  describe "business day boundary" do
    test "before 5 am the stop ends the same morning, after it the next morning" do
      night = DateTime.new!(~D[2026-10-27], ~T[03:00:00], "Europe/Moscow")
      evening = DateTime.new!(~D[2026-10-27], ~T[21:00:00], "Europe/Moscow")

      assert StopPeriod.until(:today, night) == ~U[2026-10-27 02:00:00Z]
      assert StopPeriod.until(:today, evening) == ~U[2026-10-28 02:00:00Z]
    end
  end

  describe "external stops" do
    test "replace the set of a source and keep manual stops", %{staff: staff, branch: branch} do
      [soup, tea, pizza] =
        for name <- ~w(Soup Tea Pizza), do: insert_branch_product(branch.id, name: name)

      {:ok, _} = Stops.stop(staff, branch.id, pizza, :until_resumed)

      assert {:ok, true} = Stops.replace_external(branch.id, :frontpad, [soup.id, tea.id])
      assert {:ok, false} = Stops.replace_external(branch.id, :frontpad, [soup.id, tea.id])
      assert {:ok, true} = Stops.replace_external(branch.id, :frontpad, [tea.id])

      assert Stops.stopped_ids(branch.id) == MapSet.new([tea.id, pizza.id])
    end
  end

  describe "ordering" do
    test "stopped products cannot be added to a cart or ordered", %{staff: staff, branch: branch} do
      product = insert_branch_product(branch.id, price: 100)
      {:ok, cart} = Carts.create_cart(%{session_id: "stops-#{branch.id}", branch_id: branch.id})
      {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

      {:ok, _} = Stops.stop(staff, branch.id, product, :today)

      assert {:error, :product_unavailable} = Carts.add_item(cart.id, product.id, 1)

      assert {:error, :stops, :product_unavailable} =
               Oms.create_order(%{
                 "cart_id" => cart.id,
                 "branch_id" => branch.id,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               })
    end
  end
end
