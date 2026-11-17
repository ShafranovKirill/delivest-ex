defmodule Delivest.Analytics.SalesCacheWorker do
  @moduledoc "Bounded nightly/on-demand reconciliation of dirty base-sales days."
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker], states: [:available, :scheduled, :retryable]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Delivest.Analytics.SalesCache.rebuild_batch() >= 12 do
      %{} |> new(schedule_in: 1) |> Oban.insert()
    end

    :ok
  end
end
