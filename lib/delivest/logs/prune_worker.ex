defmodule Delivest.Logs.PruneWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Delivest.Logs

  @impl Oban.Worker
  def perform(_job) do
    {count, _} = Logs.prune(Logs.retention_days())
    {:ok, count}
  end
end
