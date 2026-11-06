defmodule Delivest.Integrations.Rkeeper.PollWorker do
  use Oban.Worker,
    queue: :rkeeper_polling,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:order_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Delivest.Integrations.Rkeeper

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(15 * attempt * attempt, 300)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}), do: Rkeeper.poll_order(order_id)
end
