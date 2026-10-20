defmodule Delivest.Oms.Workers.StaleOrderWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  require Logger

  alias Delivest.LocalTime
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Repo

  @open_statuses [:created, :preparing, :ready, :delivering]

  @impl Oban.Worker
  def perform(_job) do
    cancelled = cancel_stale(stale_hours())
    if cancelled > 0, do: Logger.info("auto-cancelled #{cancelled} stale orders")
    {:ok, cancelled}
  end

  @spec cancel_stale(pos_integer(), DateTime.t()) :: non_neg_integer()
  def cancel_stale(hours, now \\ DateTime.utc_now()) do
    hours
    |> stale_query(now)
    |> Repo.all()
    |> Enum.count(&match?({:ok, _}, cancel(&1)))
  end

  defp stale_query(hours, now) do
    cutoff = DateTime.add(now, -hours, :hour)
    local_cutoff = LocalTime.utc_to_naive(cutoff)

    from(o in Order,
      where: o.status in ^@open_statuses and is_nil(o.deleted_at),
      where: o.inserted_at < ^cutoff,
      where: is_nil(o.cook_by) or o.cook_by < ^local_cutoff
    )
  end

  defp cancel(%Order{} = order) do
    Orders.update_order_details(order, %{
      "status" => "cancelled",
      "payment_method" => to_string(order.payment_method)
    })
  end

  defp stale_hours, do: Application.get_env(:delivest, :stale_order_hours, 24)
end
