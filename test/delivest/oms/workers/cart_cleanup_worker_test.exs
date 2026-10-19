defmodule Delivest.Oms.Workers.CartCleanupWorkerTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Oms.{Cart, Carts, Orders}
  alias Delivest.Oms.Workers.CartCleanupWorker

  @branch_id "00000000-0000-4000-8000-000000000002"

  defp age!(cart_id, days) do
    old = DateTime.add(DateTime.utc_now(:second), -days, :day)
    Repo.update_all(from(c in Cart, where: c.id == ^cart_id), set: [updated_at: old])
  end

  test "deletes old abandoned carts and keeps fresh or ordered ones" do
    product = insert_branch_product(@branch_id, price: 100)

    {:ok, abandoned} = Carts.create_cart(%{session_id: "old", branch_id: @branch_id})
    {:ok, fresh} = Carts.create_cart(%{session_id: "fresh", branch_id: @branch_id})
    {:ok, ordered} = Carts.create_cart(%{session_id: "ordered", branch_id: @branch_id})
    {:ok, _, _} = Carts.add_item(ordered.id, product.id, 1)

    {:ok, _order} =
      Orders.create_order(%{
        "cart_id" => ordered.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    age!(abandoned.id, 40)
    age!(ordered.id, 40)

    assert {:ok, 1} = perform_job(CartCleanupWorker, %{})

    refute Repo.get(Cart, abandoned.id)
    assert Repo.get(Cart, fresh.id)
    assert Repo.get(Cart, ordered.id)
  end

  defp perform_job(worker, args), do: worker.perform(%Oban.Job{args: args})
end
