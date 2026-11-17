defmodule Delivest.Analytics.SalesCacheTest do
  use Delivest.DataCase, async: true
  import Delivest.Factory
  alias Delivest.{Analytics, LocalTime}
  alias Delivest.Analytics.SalesCache
  alias Delivest.Oms.{Carts, Orders, Order}

  defp order!(branch, product, quantity, at, attrs \\ %{}) do
    {:ok, cart} =
      Carts.create_cart(%{
        session_id: "sales-cache-#{System.unique_integer()}",
        branch_id: branch.id
      })

    {:ok, _, _} = Carts.add_item(cart.id, product.id, quantity)

    {:ok, order} =
      Orders.create_order(
        Map.merge(
          %{"cart_id" => cart.id, "fulfillment_type" => "pickup", "payment_method" => "cash"},
          attrs
        )
      )

    Repo.update!(Ecto.Changeset.change(order, inserted_at: at))
  end

  defp fixture(zone \\ "Europe/Moscow") do
    branch = insert(:branch)
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: branch.id, timezone: zone})
    category = insert(:category)
    product = insert_branch_product(branch.id, price: 101, category_id: category.id)
    {branch, product}
  end

  defp warm(branch, day) do
    Analytics.summary(branch.id, {day, day})
    assert {:ok, _} = SalesCache.rebuild_day(branch.id, day)

    assert [[false]] =
             Repo.query!(
               "SELECT dirty FROM sales_daily_rollups WHERE branch_id=$1::uuid AND day=$2",
               [Ecto.UUID.dump!(branch.id), day]
             ).rows
  end

  test "clean historical rollups match raw metrics across local days and branches" do
    {a, product} = fixture()
    {b, foreign} = fixture("Asia/Yekaterinburg")
    {:ok, _} = Delivest.Relations.create_relation(Repo, "Branch", b.id, "Product", product.id)
    first = order!(a, product, 1, ~U[2026-10-18 10:00:00Z])
    second = order!(a, product, 2, ~U[2026-10-19 10:00:00Z])
    third = order!(b, product, 4, ~U[2026-10-19 10:00:00Z])
    order!(b, foreign, 2, ~U[2026-10-19 11:00:00Z])

    for {order, seconds} <- [{first, 10}, {second, 20}, {third, 90}] do
      order
      |> Ecto.Changeset.change(status: :accepted)
      |> Order.crm_changeset(%{
        provider: "frontpad",
        status: "sent",
        sent_at: DateTime.add(order.inserted_at, seconds)
      })
      |> Repo.update!()
    end

    for branch <- [a, b], day <- [~D[2026-10-18], ~D[2026-10-19]], do: warm(branch, day)
    ids = [a.id, b.id, a.id]
    period = {~D[2026-10-18], ~D[2026-10-19]}
    assert Analytics.summary(ids, period) == Analytics.raw_summary(ids, period)
    assert Analytics.crm_split(ids, period) == Analytics.raw_crm_split(ids, period)
    assert Analytics.daily(ids, period) == Analytics.raw_daily(ids, period)
    assert Analytics.hourly(ids, period) == Analytics.raw_hourly(ids, period)

    assert Analytics.top_products(ids, period, limit: 1) ==
             Analytics.raw_top_products(ids, period, limit: 1)

    assert Analytics.categories(ids, period) == Analytics.raw_categories(ids, period)
    assert Analytics.status_counts(ids, period) == Analytics.raw_status_counts(ids, period)

    for field <- [:fulfillment_type, :payment_method],
        do:
          assert(
            Analytics.breakdown(ids, period, field) == Analytics.raw_breakdown(ids, period, field)
          )

    assert %{avg_confirm_seconds: 40} = Analytics.crm_split(ids, period)

    assert Enum.find(Analytics.categories(ids, period), &(&1.category_id == product.category_id)).products ==
             1
  end

  test "historical order and item updates invalidate immediately, then rebuild matches source" do
    {branch, product} = fixture()
    day = ~D[2026-10-19]
    order = order!(branch, product, 2, ~U[2026-10-19 10:00:00Z])
    warm(branch, day)
    Repo.update!(Ecto.Changeset.change(order, total_amount: 999))
    assert %{revenue: 999} = Analytics.summary(branch.id, {day, day})
    warm(branch, day)
    [item] = Repo.preload(order, :items).items
    Repo.update!(Ecto.Changeset.change(item, price: 777, quantity: 3))
    assert [%{revenue: 2331, quantity: 3}] = Analytics.top_products(branch.id, {day, day})
    warm(branch, day)
    Repo.delete!(item)
    assert [] = Analytics.top_products(branch.id, {day, day})
    warm(branch, day)
    Orders.soft_delete_order(order)
    assert %{orders_count: 0} = Analytics.summary(branch.id, {day, day})
  end

  test "moving an order invalidates both old and new local days" do
    {branch, product} = fixture()
    order = order!(branch, product, 1, ~U[2026-10-19 10:00:00Z])
    for day <- [~D[2026-10-19], ~D[2026-10-20]], do: warm(branch, day)
    Repo.update!(Ecto.Changeset.change(order, inserted_at: ~U[2026-10-20 10:00:00Z]))

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM sales_daily_rollups WHERE branch_id=$1::uuid AND day BETWEEN $2 AND $3 AND dirty",
               [Ecto.UUID.dump!(branch.id), ~D[2026-10-19], ~D[2026-10-20]]
             ).rows

    assert %{orders_count: 0} = Analytics.summary(branch.id, {~D[2026-10-19], ~D[2026-10-19]})
    assert %{orders_count: 1} = Analytics.summary(branch.id, {~D[2026-10-20], ~D[2026-10-20]})
  end

  test "timezone changes invalidate history and rebucket with the new branch zone" do
    {branch, product} = fixture()
    order!(branch, product, 1, ~U[2026-10-18 20:30:00Z])
    for day <- [~D[2026-10-18], ~D[2026-10-19]], do: warm(branch, day)
    assert %{orders_count: 0} = Analytics.summary(branch.id, {~D[2026-10-19], ~D[2026-10-19]})

    Repo.update_all(
      from(i in Delivest.Identity.Branch.BranchInfo, where: i.branch_id == ^branch.id),
      set: [timezone: "Asia/Yekaterinburg"]
    )

    warm(branch, ~D[2026-10-19])
    assert %{orders_count: 1} = Analytics.summary(branch.id, {~D[2026-10-19], ~D[2026-10-19]})
  end

  test "current day remains fresh across repeated reads in the same process" do
    {branch, product} = fixture()
    day = LocalTime.today(LocalTime.timezone(branch.id))
    order = order!(branch, product, 1, DateTime.utc_now() |> DateTime.truncate(:second))
    assert %{revenue: 101} = Analytics.summary(branch.id, {day, day})
    Repo.update!(Ecto.Changeset.change(order, total_amount: 404))
    assert %{revenue: 404} = Analytics.summary(branch.id, {day, day})

    assert [[true, nil]] =
             Repo.query!(
               "SELECT dirty,payload FROM sales_daily_rollups WHERE branch_id=$1::uuid AND day=$2",
               [Ecto.UUID.dump!(branch.id), day]
             ).rows
  end

  test "a source revision racing calculation cannot publish a clean stale snapshot" do
    {branch, product} = fixture()
    day = ~D[2026-10-19]
    order = order!(branch, product, 1, ~U[2026-10-19 10:00:00Z])
    warm(branch, day)
    Repo.update!(Ecto.Changeset.change(order, total_amount: 202))
    handler = {__MODULE__, make_ref()}
    owner = self()

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == owner and String.contains?(metadata.query, "array_agg(DISTINCT") and
             not Process.get(handler, false) do
          Process.put(handler, true)
          Repo.update!(Ecto.Changeset.change(order, total_amount: 909))
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, %{num_rows: 0}} = SalesCache.rebuild_day(branch.id, day)

    assert [[true]] =
             Repo.query!(
               "SELECT dirty FROM sales_daily_rollups WHERE branch_id=$1::uuid AND day=$2",
               [Ecto.UUID.dump!(branch.id), day]
             ).rows

    assert %{revenue: 909} = Analytics.summary(branch.id, {day, day})
    warm(branch, day)
    assert %{revenue: 909} = Analytics.summary(branch.id, {day, day})
  end

  test "current-day payload is reused across comparison and other screen metrics" do
    {branch, product} = fixture()
    today = LocalTime.today(LocalTime.timezone(branch.id))
    yesterday = Date.add(today, -1)
    order!(branch, product, 1, DateTime.utc_now() |> DateTime.truncate(:second))
    warm(branch, yesterday)
    handler = {__MODULE__, make_ref()}
    owner = self()
    Process.put(handler, 0)

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == owner and String.contains?(metadata.query, "array_agg(DISTINCT") do
          Process.put(handler, Process.get(handler, 0) + 1)
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    Analytics.summary(branch.id, {today, today})
    Analytics.summary(branch.id, {yesterday, yesterday})
    Analytics.crm_split(branch.id, {today, today})
    Analytics.hourly(branch.id, {today, today})
    assert Process.get(handler) == 1
  end
end
