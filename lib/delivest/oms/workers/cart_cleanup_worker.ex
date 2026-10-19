defmodule Delivest.Oms.Workers.CartCleanupWorker do
  @moduledoc """
  Deletes abandoned carts: every visitor gets a cart, and nothing else ever removes them.

  Carts referenced by an order are kept, because order editing in the admin panel
  reuses the order's cart.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Delivest.Oms.{Cart, Order}
  alias Delivest.Repo

  @max_age_days 30

  @impl Oban.Worker
  def perform(_job) do
    {count, _} = delete_abandoned_carts(@max_age_days)
    {:ok, count}
  end

  @spec delete_abandoned_carts(pos_integer()) :: {non_neg_integer(), nil}
  def delete_abandoned_carts(max_age_days) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days, :day)

    from(c in Cart,
      as: :cart,
      where: c.updated_at < ^cutoff,
      where: not exists(from(o in Order, where: o.cart_id == parent_as(:cart).id))
    )
    |> Repo.delete_all()
  end
end
