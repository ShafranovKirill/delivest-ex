defmodule Delivest.Events.DeliverWorker do
  use Oban.Worker,
    queue: :events,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:event_id, :subscriber]]

  require Logger
  import Ecto.Query

  alias Delivest.Events.{Delivery, Event, Registry}
  alias Delivest.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)) * 5, 1800)

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"subscriber" => "payments"}}), do: 180_000
  def timeout(_job), do: 15_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id, "subscriber" => key}}) do
    case Registry.fetch(key) do
      {:ok, module} -> deliver(id, key, module)
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp deliver(id, key, module) do
    result =
      Repo.transaction(
        fn ->
          # The HTTP subscriber has a 15 second receive timeout; several payments may be handled.
          Repo.query!("SET LOCAL statement_timeout = '175s'")
          Repo.query!("SET LOCAL idle_in_transaction_session_timeout = '175s'")

          case Repo.get(Event, id) do
            nil -> Repo.rollback(:event_not_found)
            event -> locked_delivery(event, key, module)
          end
        end,
        timeout: if(key == "payments", do: 180_000, else: 15_000)
      )

    case result do
      {:ok, {:delivered, event}} ->
        notify_after_commit(module, event, key)
        report_delivery(event, key)
        :ok

      {:ok, :already_done} ->
        :ok

      {:ok, :busy} ->
        {:snooze, 5}

      {:error, {:cancel, reason}} ->
        {:cancel, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp locked_delivery(event, key, module) do
    lock_key = "#{event.aggregate_type}:#{event.aggregate_id}:#{key}"

    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])

    if locked? do
      delivery =
        Repo.get_by(Delivery, event_id: event.id, subscriber: key) ||
          bridge_legacy_delivery(event, key)

      case delivery.status do
        status when status in ["delivered", "resolved"] ->
          :already_done

        "pending" ->
          if predecessor_pending?(event, key) do
            :busy
          else
            case module.handle(event) do
              :ok -> acknowledge(event, key)
              {:ok, _} -> acknowledge(event, key)
              {:cancel, reason} -> Repo.rollback({:cancel, reason})
              {:error, reason} -> Repo.rollback(reason)
            end
          end
      end
    else
      :busy
    end
  end

  defp bridge_legacy_delivery(event, key) do
    now = DateTime.utc_now()

    Repo.insert!(
      %Delivery{
        event_id: event.id,
        subscriber: key,
        status: "pending",
        inserted_at: now,
        updated_at: now
      },
      on_conflict: :nothing
    )

    Repo.get_by!(Delivery, event_id: event.id, subscriber: key)
  end

  defp predecessor_pending?(event, key) do
    Repo.exists?(
      from d in Delivery,
        join: earlier in Event,
        on: earlier.id == d.event_id,
        where: d.subscriber == ^key and d.status == "pending",
        where: earlier.aggregate_type == ^event.aggregate_type,
        where: earlier.aggregate_id == ^event.aggregate_id and earlier.sequence < ^event.sequence
    )
  end

  defp acknowledge(event, key) do
    now = DateTime.utc_now()

    {1, _} =
      Repo.update_all(
        from(d in Delivery,
          where: d.event_id == ^event.id and d.subscriber == ^key and d.status == "pending"
        ),
        set: [status: "delivered", delivered_at: now, updated_at: now]
      )

    {:delivered, event}
  end

  defp report_delivery(event, key) do
    lag = DateTime.diff(DateTime.utc_now(), event.inserted_at, :millisecond)

    :telemetry.execute(
      [:delivest, :outbox, :delivered],
      %{count: 1, lag: lag},
      %{subscriber: to_string(key)}
    )
  end

  defp notify_after_commit(module, event, key) do
    if function_exported?(module, :after_commit, 1) do
      try do
        case module.after_commit(event) do
          :ok -> :ok
          _other -> Logger.error("post-commit notification failed for #{key} event #{event.id}")
        end
      rescue
        _error -> Logger.error("post-commit notification raised for #{key} event #{event.id}")
      catch
        kind, _reason ->
          Logger.error("post-commit notification failed (#{kind}) for #{key} event #{event.id}")
      end
    end
  end
end
