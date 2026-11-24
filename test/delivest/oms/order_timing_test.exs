defmodule Delivest.Oms.OrderTimingTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.OrderTiming
  alias Delivest.Oms.OrderTiming.Settings

  setup do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, delivery_time: 45})

    staff =
      insert(:staff, role: insert(:role, permissions: ["branches.update", "delivery.update"]))

    insert(:staff_branch, branch: branch, staff: staff)
    %{branch: branch, staff: staff}
  end

  test "fixed delivery is the complete customer time and has no kitchen promise", %{
    branch: branch
  } do
    now = DateTime.utc_now(:second)
    estimate = OrderTiming.estimate(branch.id, :delivery, [], nil, now)
    assert estimate.total_minutes == 45
    assert estimate.ready_at == nil
    assert estimate.delivered_at == DateTime.add(now, 45, :minute)
  end

  test "branch rules use parallel products, category fallback, and one packing allowance", %{
    branch: branch,
    staff: staff
  } do
    category = insert(:category)

    {:ok, _} =
      Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    product = insert_branch_product(branch.id, category_id: category.id)

    assert {:ok, settings} =
             OrderTiming.update(staff, branch.id, %{
               "mode" => "calculated",
               "kitchen_minutes" => "25",
               "packing_minutes" => "3",
               "travel_minutes" => "35",
               "category_minutes" => %{category.id => "12"},
               "product_minutes" => %{product.id => "20"}
             })

    assert settings.mode == :calculated
    assert settings.product_minutes[product.id] == 20

    items = [
      %{product_id: product.id, category_id: category.id},
      %{product_id: Ecto.UUID.generate(), category_id: category.id}
    ]

    assert OrderTiming.prep_minutes(settings, items) == 25
    assert OrderTiming.estimate(branch.id, :delivery, items, 18).total_minutes == 43
    assert OrderTiming.estimate(branch.id, :delivery, items).total_minutes == 60
    assert OrderTiming.estimate(branch.id, :pickup, items).total_minutes == 25
  end

  test "volume allowance counts portions in one line and across lines" do
    product = Ecto.UUID.generate()
    settings = %Settings{product_minutes: %{product => 30}}
    one_line = [%{product_id: product, quantity: 5}]
    split_lines = List.duplicate(%{product_id: product}, 5)

    assert OrderTiming.prep_minutes(settings, one_line) == 42
    assert OrderTiming.prep_minutes(settings, split_lines) == 42
    assert OrderTiming.prep_minutes(settings, [%{product_id: product}]) == 30
  end

  test "mixed products add ten percent of work beyond the longest portion, rounded up" do
    short = Ecto.UUID.generate()
    medium = Ecto.UUID.generate()
    long = Ecto.UUID.generate()

    settings = %Settings{product_minutes: %{short => 10, medium => 20, long => 30}}

    items = [
      %{product_id: short, quantity: 2},
      %{product_id: medium, quantity: 2},
      %{product_id: long, quantity: 1}
    ]

    assert OrderTiming.prep_minutes(settings, items) == 36
  end

  test "volume rounding, unavailable exclusion, empty fallback, and existing allowances" do
    short = Ecto.UUID.generate()
    long = Ecto.UUID.generate()
    settings = %Settings{product_minutes: %{short => 1, long => 30}, packing_minutes: 3}

    assert OrderTiming.prep_minutes(settings, [%{product_id: long}, %{product_id: short}], 2) ==
             36

    assert OrderTiming.prep_minutes(settings, [%{product_id: long, quantity: 2}], 2) == 38

    assert OrderTiming.prep_minutes(settings, [
             %{product_id: short},
             %{product_id: long, quantity: 5, unavailable: true}
           ]) == 4

    assert OrderTiming.prep_minutes(settings, [], 2) == 30
  end

  test "delivery form changes one source of settings without dropping product rules", %{
    branch: branch,
    staff: staff
  } do
    product = insert_branch_product(branch.id)

    assert {:ok, _} =
             OrderTiming.update(staff, branch.id, %{
               mode: "calculated",
               product_minutes: %{product.id => "17"}
             })

    assert {:ok, settings} =
             OrderTiming.update_delivery(staff, branch.id, %{
               "mode" => "fixed",
               "fixed_delivery_minutes" => "15"
             })

    assert settings.mode == :fixed
    assert settings.product_minutes[product.id] == 17
    assert OrderTiming.fixed_minutes(branch.id) == 15
    assert OrderTiming.estimate(branch.id, :delivery, []).total_minutes == 15

    assert {:error, :foreign_timing_override} =
             OrderTiming.update(staff, branch.id, %{
               product_minutes: %{Ecto.UUID.generate() => "10"}
             })
  end

  test "warm cart time calculation runs without SQL", %{branch: branch, staff: staff} do
    assert {:ok, _} = OrderTiming.update(staff, branch.id, %{mode: "calculated"})
    {:ok, _branch} = Identity.get_branch(branch.id, preload: :info)
    items = [%{product_id: Ecto.UUID.generate(), category_id: nil}]
    event = [:delivest, :repo, :query]
    handler = "order-timing-sql-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn _, _, metadata, _ ->
          if self() == parent, do: send(parent, {:timing_sql, metadata.query})
        end,
        nil
      )

    try do
      assert OrderTiming.cart_prep_minutes(branch.id, items) == 25
      refute_receive {:timing_sql, _query}
    after
      :telemetry.detach(handler)
    end
  end
end
