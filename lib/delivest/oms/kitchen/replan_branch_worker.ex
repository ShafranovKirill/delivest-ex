defmodule Delivest.Oms.Kitchen.ReplanBranchWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:branch_id], period: :infinity, states: [:available, :scheduled, :retryable]]

  require Logger

  alias Delivest.Oms.Kitchen

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id}}) do
    result =
      :global.trans(
        {{__MODULE__, branch_id}, self()},
        fn -> Kitchen.reschedule_branch(branch_id) end,
        [node()]
      )

    case result do
      :ok ->
        :ok

      :aborted ->
        Logger.error("kitchen replan for branch #{branch_id} could not acquire its lock")
        {:error, :lock_unavailable}

      {:error, reason} = error ->
        Logger.error("kitchen replan for branch #{branch_id} failed: #{inspect(reason)}")
        error
    end
  end
end
