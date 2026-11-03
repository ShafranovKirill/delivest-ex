defmodule Delivest.Events.DeliverWorker do
  use Oban.Worker,
    queue: :events,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:event_id, :subscriber]]

  require Logger

  alias Delivest.Events.{Event, Registry}
  alias Delivest.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)) * 5, 1800)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id, "subscriber" => key}} = job) do
    with {:ok, module} <- Registry.fetch(key),
         %Event{} = event <- Repo.get(Event, id) || {:error, :event_not_found} do
      event |> module.handle() |> result(event, key, job)
    else
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp result(:ok, event, key, _job) do
    report_delivery(event, key)
    :ok
  end

  defp result({:ok, _value}, event, key, job), do: result(:ok, event, key, job)

  defp result({:cancel, reason} = cancel, event, key, _job) do
    Logger.error("event #{event.type} #{event.id} cancelled for #{key}: #{inspect(reason)}")
    cancel
  end

  defp result({:error, reason} = error, event, key, %Oban.Job{attempt: attempt} = job)
       when attempt >= job.max_attempts do
    Logger.error("event #{event.type} #{event.id} not delivered to #{key}: #{inspect(reason)}")
    error
  end

  defp result({:error, _reason} = error, _event, _key, _job), do: error

  defp report_delivery(event, key) do
    lag = DateTime.diff(DateTime.utc_now(), event.inserted_at, :millisecond)

    :telemetry.execute(
      [:delivest, :outbox, :delivered],
      %{count: 1, lag: lag},
      %{subscriber: to_string(key)}
    )
  end
end
