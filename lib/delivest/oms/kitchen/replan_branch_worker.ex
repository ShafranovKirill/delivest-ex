defmodule Delivest.Oms.Kitchen.ReplanBranchWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:branch_id], period: :infinity, states: [:available, :scheduled, :retryable]]

  require Logger

  alias Delivest.Oms.Kitchen

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id}}) do
    case Kitchen.reschedule_branch(branch_id) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("kitchen replan for branch #{branch_id} failed: #{inspect(reason)}")
        error
    end
  end
end
