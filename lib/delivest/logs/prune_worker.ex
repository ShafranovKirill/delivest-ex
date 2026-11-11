defmodule Delivest.Logs.PruneWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Delivest.{Audit, Funnel, Logs}
  alias Delivest.Advertising.Clicks
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
    funnel = Funnel.prune()
    advertising_clicks = Clicks.prune()
    advertising_claims = Clicks.prune_claims()

    # Each job stays bounded. If a backlog remains, continue through the core
    # maintenance queue without depending on the capture feature gate.
    if funnel.events == Funnel.prune_batch() or funnel.sessions == Funnel.prune_batch() or
         advertising_clicks == Clicks.prune_batch() or
         advertising_claims == Clicks.prune_batch() do
      {:ok, _} =
        __MODULE__.new(%{"continuation" => true},
          schedule_in: 1,
          unique: [
            period: 60,
            fields: [:worker, :args],
            states: [:available, :scheduled, :retryable]
          ]
        )
        |> Oban.insert()
    end

    {:ok,
     %{
       logs: logs,
       events: events,
       requests: requests,
       inbox: inbox,
       confirmations: confirmations,
       funnel: funnel,
       advertising_clicks: advertising_clicks,
       advertising_claims: advertising_claims
     }}
  end
end
