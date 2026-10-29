defmodule Delivest.Logs.PruneWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Delivest.{Audit, Logs}
  alias Delivest.Integrations.{Inbox, Journal}

  @impl Oban.Worker
  def perform(_job) do
    logs = Logs.prune(Logs.retention_days(), Logs.error_retention_days())
    events = Audit.prune(Audit.retention_days())
    requests = Journal.prune(Logs.retention_days())
    inbox = Inbox.prune(Logs.retention_days())
    {:ok, %{logs: logs, events: events, requests: requests, inbox: inbox}}
  end
end
