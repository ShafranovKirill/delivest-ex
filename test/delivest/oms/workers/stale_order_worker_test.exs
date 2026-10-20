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

  test "cancels open orders older than the threshold" do
    stale = order_at(~U[2026-10-19 10:00:00Z])
    fresh = order_at(~U[2026-10-20 08:00:00Z])
    done = order_at(~U[2026-10-18 10:00:00Z], status: :completed)

    assert StaleOrderWorker.cancel_stale(24, @now) == 1

    assert Repo.reload!(stale).status == :cancelled
    assert Repo.reload!(fresh).status == :created
    assert Repo.reload!(done).status == :completed
  end

  test "keeps preorders scheduled for later" do
    preorder = order_at(~U[2026-10-18 10:00:00Z], cook_by: ~N[2026-10-21 12:00:00])

    assert StaleOrderWorker.cancel_stale(24, @now) == 0
    assert %Order{status: :created} = Repo.reload!(preorder)
  end

  test "leaves crm orders to the crm" do
    crm = order_at(~U[2026-10-18 10:00:00Z], status: :crm)

    assert StaleOrderWorker.cancel_stale(24, @now) == 0
    assert Repo.reload!(crm).status == :crm
  end
end
