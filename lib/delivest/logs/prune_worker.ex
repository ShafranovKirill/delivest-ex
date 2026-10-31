defmodule Delivest.Logs.PruneWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Delivest.{Audit, Logs}
  alias Delivest.Identity.PhoneConfirmations
  alias Delivest.Integrations.{Inbox, Journal}

  @confirmation_days 7

  @impl Oban.Worker
  def perform(_job) do
    logs = Logs.prune(Logs.retention_days(), Logs.error_retention_days())
    events = Audit.prune(Audit.retention_days())
    requests = Journal.prune(Logs.retention_days())
    inbox = Inbox.prune(Logs.retention_days())
    confirmations = PhoneConfirmations.prune(@confirmation_days)

    {:ok,
     %{
       logs: logs,
       events: events,
       requests: requests,
       inbox: inbox,
       confirmations: confirmations
     }}
  end
end
