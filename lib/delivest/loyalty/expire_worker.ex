defmodule Delivest.Loyalty.ExpireWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    amount = Delivest.Loyalty.expire_due(now)

    if Delivest.Loyalty.due_entries?(now), do: {:snooze, 1}, else: {:ok, amount}
  end
end
