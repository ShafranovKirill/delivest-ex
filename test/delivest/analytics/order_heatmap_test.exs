defmodule Delivest.Analytics.OrderHeatmapTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Analytics.OrderHeatmap, Repo}
  alias Delivest.Identity.Branch.BranchInfo

  setup do
    a = insert(:branch, is_active: true)
    b = insert(:branch, is_active: true)

    staff =
      insert(:staff, role: insert(:role, permissions: ["statistics.read", "statistics.network"]))

    insert(:staff_branch, staff: staff, branch: a)
    insert(:staff_branch, staff: staff, branch: b)
    %{a: a, b: b, staff: Repo.preload(staff, [:role, :branches])}
  end

  test "four full weeks count zero weekdays; cancellations and fulfillment are included", %{
    a: a,
    staff: staff
  } do
    period = {~D[2026-10-26], ~D[2026-11-22]}
    monday = ~D[2026-10-26]

    for _ <- 1..72 do
      order = order_fixture(a.id, price: 100)
      at = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")

      Repo.update!(
        Ecto.Changeset.change(order,
          inserted_at: at,
          status: :cancelled,
          fulfillment_type: :pickup
        )
      )
    end

    assert {:ok, data} = OrderHeatmap.read(staff, {:branch, a.id}, period)
    assert length(data.cells) == 168

    assert %{total: 72, dates: 4, average: 18.0} =
             Enum.find(data.cells, &(&1.day == 1 and &1.hour == 14))

    assert %{total: 0, dates: 4} = Enum.find(data.cells, &(&1.day == 5 and &1.hour == 14))

    assert {:ok, pickup} = OrderHeatmap.read(staff, {:branch, a.id}, period, "pickup")
    assert Enum.sum(Enum.map(pickup.cells, & &1.total)) == 72
    assert {:ok, delivery} = OrderHeatmap.read(staff, {:branch, a.id}, period, "delivery")
    assert Enum.sum(Enum.map(delivery.cells, & &1.total)) == 0
    assert {:ok, details} = OrderHeatmap.detail(staff, {:branch, a.id}, period, "all", 5, 14)
    assert length(details) == 4
    assert Enum.all?(details, &(&1.total == 0))
  end

  test "DST repeated hour and following local midnight remain in their local buckets", %{
    a: a,
    staff: staff
  } do
    case Repo.preload(a, :info).info do
      nil -> Repo.insert!(%BranchInfo{branch_id: a.id, timezone: "America/New_York"})
      info -> Repo.update!(Ecto.Changeset.change(info, timezone: "America/New_York"))
    end

    for at <- [~U[2026-11-01 05:30:00Z], ~U[2026-11-01 06:30:00Z], ~U[2026-11-02 05:30:00Z]] do
      order = order_fixture(a.id, price: 100)
      Repo.update!(Ecto.Changeset.change(order, inserted_at: at))
    end

    period = {~D[2026-10-26], ~D[2026-11-22]}
    assert {:ok, data} = OrderHeatmap.read(staff, {:branch, a.id}, period)
    assert %{total: 2, average: 0.5} = Enum.find(data.cells, &(&1.day == 7 and &1.hour == 1))
    assert %{total: 1, average: 0.25} = Enum.find(data.cells, &(&1.day == 1 and &1.hour == 0))
    assert {:ok, details} = OrderHeatmap.detail(staff, {:branch, a.id}, period, "all", 7, 1)
    assert Enum.find(details, &(&1.date == ~D[2026-11-01])).total == 2
  end

  test "four Fridays include an observed zero Friday in the average", %{a: a, staff: staff} do
    period = {~D[2026-10-26], ~D[2026-11-22]}

    for friday <- [~D[2026-10-30], ~D[2026-11-06], ~D[2026-11-13]],
        _ <- 1..24 do
      order = order_fixture(a.id, price: 100)
      at = DateTime.new!(friday, ~T[13:00:00], "Etc/UTC")
      Repo.update!(Ecto.Changeset.change(order, inserted_at: at, status: :cancelled))
    end

    assert {:ok, heatmap} = OrderHeatmap.read(staff, {:branch, a.id}, period)

    assert %{total: 72, dates: 4, average: 18.0} =
             Enum.find(heatmap.cells, &(&1.day == 5 and &1.hour == 16))

    assert {:ok, details} = OrderHeatmap.detail(staff, {:branch, a.id}, period, "all", 5, 16)
    assert Enum.map(details, & &1.total) == [24, 24, 24, 0]
  end

  test "network denominator is calendar dates, branch-local midnight is applied", %{
    a: a,
    b: b,
    staff: staff
  } do
    period = {~D[2026-10-26], ~D[2026-11-22]}

    for branch <- [a, b] do
      order = order_fixture(branch.id, price: 100)

      Repo.update!(
        Ecto.Changeset.change(order, inserted_at: ~U[2026-10-25 22:30:00Z], status: :cancelled)
      )
    end

    assert {:ok, network} = OrderHeatmap.read(staff, :network, period)

    assert %{total: 2, dates: 4, average: 0.5} =
             Enum.find(network.cells, &(&1.day == 1 and &1.hour == 1))

    assert {:ok, scoped} = OrderHeatmap.read(staff, :network, period, "all", a.id)

    assert %{total: 1, dates: 4, average: 0.25} =
             Enum.find(scoped.cells, &(&1.day == 1 and &1.hour == 1))
  end

  test "invalid range, fulfillment and foreign detail are rejected", %{a: a, staff: staff} do
    period = {~D[2026-10-26], ~D[2026-11-22]}
    outsider = insert(:branch)

    assert {:error, :invalid_period} =
             OrderHeatmap.read(staff, :network, {~D[2026-10-27], ~D[2026-11-22]})

    assert {:error, :invalid_fulfillment} = OrderHeatmap.read(staff, :network, period, "other")
    assert {:error, :forbidden} = OrderHeatmap.read(staff, {:branch, outsider.id}, period)
    assert {:error, :forbidden} = OrderHeatmap.read(staff, :network, period, "all", outsider.id)

    assert {:error, :forbidden} =
             OrderHeatmap.detail(staff, :network, period, "all", 1, 1, outsider.id)

    assert {:error, :forbidden} =
             OrderHeatmap.detail(staff, {:branch, a.id}, period, "all", 1, 1, outsider.id)

    assert {:error, :invalid_cell} = OrderHeatmap.detail(staff, :network, period, "all", 8, 24)
  end

  test "network with no assigned branches stays empty and keeps zero denominators" do
    staff =
      insert(:staff, role: insert(:role, permissions: ["statistics.read", "statistics.network"]))

    staff = Repo.preload(staff, [:role, :branches])
    period = {~D[2026-10-26], ~D[2026-11-22]}

    assert {:ok, %{state: :no_branches, branches: [], cells: cells}} =
             OrderHeatmap.read(staff, :network, period)

    assert length(cells) == 168
    assert Enum.all?(cells, &(&1.total == 0 and &1.dates == 4))
  end
end
