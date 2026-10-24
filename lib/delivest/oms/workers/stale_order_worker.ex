defmodule Delivest.Oms.Workers.StaleOrderWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  require Logger

  alias Delivest.LocalTime
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Repo

  @open_statuses [:created, :preparing, :ready, :delivering]
  @handed_over [:ready, :delivering]
  @grace_hours 3

  @impl Oban.Worker
  def perform(_job) do
    closed = close_past_days()

    if closed.completed + closed.cancelled > 0,
      do:
        Logger.info(
          "closed orders of past days: #{closed.completed} completed, #{closed.cancelled} cancelled"
        )

    {:ok, closed}
  end

  @spec close_past_days(DateTime.t()) :: %{
          completed: non_neg_integer(),
          cancelled: non_neg_integer()
        }
  def close_past_days(now \\ DateTime.utc_now()) do
    now
    |> past_days_query()
    |> Repo.all()
    |> Enum.reduce(%{completed: 0, cancelled: 0}, fn order, acc ->
      status = final_status(order)

      case close(order, status) do
        {:ok, _order} -> Map.update!(acc, status, &(&1 + 1))
        _error -> acc
      end
    end)
  end

  defp past_days_query(now) do
    local_now = LocalTime.utc_to_naive(now)
    day_start = local_now |> NaiveDateTime.to_date() |> LocalTime.start_of_day_utc()
    local_day_start = LocalTime.utc_to_naive(day_start)
    cutoff = DateTime.add(now, -@grace_hours, :hour)
    local_cutoff = NaiveDateTime.add(local_now, -@grace_hours, :hour)

    from(o in Order,
      where: o.status in ^@open_statuses and is_nil(o.deleted_at),
      where: o.inserted_at < ^day_start and o.inserted_at < ^cutoff,
      where: is_nil(o.cook_by) or (o.cook_by < ^local_day_start and o.cook_by < ^local_cutoff)
    )
  end

  defp final_status(%Order{status: status}) when status in @handed_over, do: :completed
  defp final_status(_order), do: :cancelled

  defp close(%Order{} = order, status) do
    Orders.update_order_details(order, %{
      "status" => to_string(status),
      "payment_method" => to_string(order.payment_method),
      "cancel_reason" => "not_confirmed"
    })
  end
end
