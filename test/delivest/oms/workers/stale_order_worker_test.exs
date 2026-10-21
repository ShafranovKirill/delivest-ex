defmodule Delivest.Oms.Workers.StaleOrderWorkerTest do
  use Delivest.DataCase, async: true

  import Delivest.OrderFixtures

  alias Delivest.Oms.Order
  alias Delivest.Oms.Workers.StaleOrderWorker

  @branch_id "00000000-0000-4000-8000-0000000000c1"
  @now ~U[2026-10-20 12:00:00Z]

  defp order_at(inserted_at, changes \\ []) do
    @branch_id
    |> order_fixture()
    |> Ecto.Changeset.change([inserted_at: inserted_at] ++ changes)
    |> Repo.update!()
  end

  test "completes ready orders and cancels unfinished ones of past days" do
    ready = order_at(~U[2026-10-19 10:00:00Z], status: :ready)
    delivering = order_at(~U[2026-10-19 11:00:00Z], status: :delivering)
    created = order_at(~U[2026-10-19 12:00:00Z])
    today = order_at(~U[2026-10-20 06:00:00Z], status: :ready)
    done = order_at(~U[2026-10-18 10:00:00Z], status: :completed)

    assert StaleOrderWorker.close_past_days(@now) == %{completed: 2, cancelled: 1}

    assert Repo.reload!(ready).status == :completed
    assert Repo.reload!(delivering).status == :completed
    assert Repo.reload!(created).status == :cancelled
    assert Repo.reload!(today).status == :ready
    assert Repo.reload!(done).status == :completed
  end

  test "gives late night orders a few hours after midnight" do
    late = order_at(~U[2026-10-19 20:50:00Z], status: :ready)

    assert StaleOrderWorker.close_past_days(~U[2026-10-19 22:30:00Z]) ==
             %{completed: 0, cancelled: 0}

    assert StaleOrderWorker.close_past_days(~U[2026-10-20 01:00:00Z]) ==
             %{completed: 1, cancelled: 0}

    assert Repo.reload!(late).status == :completed
  end

  test "keeps preorders scheduled for later" do
    preorder = order_at(~U[2026-10-18 10:00:00Z], cook_by: ~N[2026-10-21 12:00:00])

    assert StaleOrderWorker.close_past_days(@now) == %{completed: 0, cancelled: 0}
    assert %Order{status: :created} = Repo.reload!(preorder)
  end

  test "leaves crm orders to the crm" do
    crm = order_at(~U[2026-10-18 10:00:00Z], status: :crm)

    assert StaleOrderWorker.close_past_days(@now) == %{completed: 0, cancelled: 0}
    assert Repo.reload!(crm).status == :crm
  end
end
