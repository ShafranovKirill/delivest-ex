defmodule Delivest.Integrations.Crm.StopSyncWorker do
  use Oban.Worker, queue: :crm, max_attempts: 1, unique: [period: 300, fields: [:args]]

  alias Delivest.Integrations.Crm.{Lookup, StopSync}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id}}) do
    case StopSync.sync(branch_id) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  def perform(%Oban.Job{}) do
    Lookup.crm_branch_ids()
    |> Enum.map(&new(%{"branch_id" => &1}))
    |> Oban.insert_all()

    :ok
  end
end
