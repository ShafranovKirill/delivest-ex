defmodule Delivest.Analytics.DeliveryQualityTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Analytics.DeliveryQuality, Repo}
  alias Delivest.DeliveryMeasurement.{ActualEvent, PromiseHistory}
  alias Delivest.Identity.Branch.BranchInfo

  test "measured denominator, inclusive deadline, missing legacy, and branch auth" do
    branch = insert(:branch, is_active: true)
    foreign = insert(:branch, is_active: true)
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    day = ~D[2026-11-22]
    created = ~U[2026-11-22 10:00:00Z]
    promise = ~U[2026-11-22 12:00:00Z]

    for n <- 1..10 do
      order = order_fixture(branch.id, price: 100)

      attrs = %{
        status: :completed,
        fulfillment_type: :delivery,
        inserted_at: created,
        initial_promised_delivery_at: if(n <= 8, do: promise),
        promised_delivery_at: if(n == 1, do: DateTime.add(promise, 3600), else: promise),
        delivery_actual_source: if(n <= 8, do: "staff_handover"),
        delivered_at:
          cond do
            n <= 6 -> promise
            n <= 8 -> DateTime.add(promise, 1, :second)
            true -> nil
          end
      }

      Repo.update!(Ecto.Changeset.change(order, attrs))

      if n <= 8 do
        Repo.insert!(%PromiseHistory{
          order_id: order.id,
          source: "staff",
          promised_at: promise,
          recorded_at: DateTime.utc_now()
        })
        Repo.insert!(%ActualEvent{
          order_id: order.id,
          source: "staff_handover",
          event_id: "staff_handover:#{order.id}",
          occurred_at: attrs.delivered_at,
          received_at: attrs.delivered_at
        })
      end
    end

    assert {:ok, %{summary: summary, daily: [%{date: ^day}]}} =
             DeliveryQuality.read(staff, {:branch, branch.id}, {day, day})

    assert %{
             total: 10,
             measured: 8,
             on_time: 6,
             late: 2,
             missing: 2,
             on_time_rate: 75.0,
             coverage: 80.0
           } = summary

    assert {:ok, %{on_time: 6}} =
             DeliveryQuality.detail(staff, {:branch, branch.id}, {day, day}, day)

    assert {:error, :forbidden} = DeliveryQuality.read(staff, {:branch, foreign.id}, {day, day})

    assert {:error, :invalid_day} =
             DeliveryQuality.detail(staff, {:branch, branch.id}, {day, day}, Date.add(day, 1))

    empty = Date.add(day, -1)

    assert {:ok, %{summary: %{measured: 0, on_time_rate: nil, coverage: nil}}} =
             DeliveryQuality.read(staff, {:branch, branch.id}, {empty, empty})

    # A singleton settings row is not required for a branch-local cohort.
    Repo.delete_all(Delivest.Franchise.Settings)
    assert {:ok, %{summary: %{total: 10, measured: 8}}} =
             DeliveryQuality.read(staff, {:branch, branch.id}, {day, day})
  end

  test "excludes other fulfillment and statuses, applies local midnight, scopes network access" do
    branch = insert(:branch, is_active: true)
    foreign = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id, timezone: "Asia/Vladivostok"})
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read", "statistics.network"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    day = ~D[2026-11-22]

    for {fulfillment, status} <- [
          {:delivery, :completed},
          {:pickup, :completed},
          {:dine_in, :completed},
          {:delivery, :cancelled},
          {:delivery, :created}
        ] do
      order = order_fixture(branch.id, price: 100)
      Repo.update!(Ecto.Changeset.change(order,
        fulfillment_type: fulfillment,
        status: status,
        inserted_at: ~U[2026-11-21 15:30:00Z]
      ))
    end

    outsider = order_fixture(foreign.id, price: 100)
    Repo.update!(Ecto.Changeset.change(outsider,
      status: :completed, fulfillment_type: :delivery, inserted_at: ~U[2026-11-21 15:30:00Z]
    ))

    assert {:ok, %{summary: %{total: 1, measured: 0, missing: 1,
                              coverage: 0.0, on_time_rate: nil}}} =
             DeliveryQuality.read(staff, :network, {day, day})
    assert {:error, :forbidden} = DeliveryQuality.read(staff, {:branch, foreign.id}, {day, day})
  end
end
