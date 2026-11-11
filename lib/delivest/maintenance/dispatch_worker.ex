defmodule Delivest.Maintenance.DispatchWorker do
  @moduledoc "Schedules only the most recent due local day for registered tasks."

  use Oban.Worker,
    queue: :maintenance_schedule,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable],
      fields: [:worker]
    ]

  import Ecto.Query

  alias Delivest.Maintenance.{DailyJob, DailyRun, Registry}
  alias Delivest.Repo

  @active_states ~w(available scheduled executing retryable)

  @impl Oban.Worker
  def perform(_job), do: dispatch()

  def dispatch(now \\ DateTime.utc_now()) do
    results =
      for task <- Registry.tasks(), scope <- Registry.scopes(task) do
        {task, scope_type, scope_id, timezone} = scope
        date = latest_due_date(now, timezone, task.hour)
        schedule(task, scope_type, scope_id, date)
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  def latest_due_date(now, timezone, hour) when hour in 0..23 do
    local_date = now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

    if DateTime.compare(now, due_at(local_date, timezone, hour)) == :lt,
      do: Date.add(local_date, -1),
      else: local_date
  end

  def due_at(date, timezone, hour) when hour in 0..23 do
    naive = NaiveDateTime.new!(date, Time.new!(hour, 0, 0))

    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, next_valid} -> DateTime.shift_zone!(next_valid, "Etc/UTC")
    end
  end

  def schedule(task, scope_type, scope_id, date) do
    with :ok <- Registry.validate(task) do
      do_schedule(task, scope_type, scope_id, date)
    end
  end

  defp do_schedule(task, scope_type, scope_id, date) do
    Repo.transaction(fn ->
      lock_key = "maintenance:#{task.key}:#{scope_type}:#{scope_id}"
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])
      reconcile(task.key, scope_type, scope_id)

      cond do
        run_exists?(task.key, scope_type, scope_id, date) ->
          :already

        active_job?(task.key, scope_type, scope_id) ->
          :busy

        true ->
          run =
            Repo.insert!(%DailyRun{
              task_key: task.key,
              scope_type: scope_type,
              scope_id: scope_id,
              local_date: date
            })

          args = %{
            task_key: task.key,
            scope_type: scope_type,
            scope_id: scope_id,
            local_date: Date.to_iso8601(date),
            run_id: run.id
          }

          case args |> DailyJob.new(max_attempts: Registry.max_attempts(task)) |> Oban.insert() do
            {:ok, %Oban.Job{conflict?: false} = job} ->
              run |> Ecto.Changeset.change(job_id: job.id) |> Repo.update!()
              :scheduled

            {:ok, %Oban.Job{conflict?: true}} ->
              Repo.rollback(:job_conflict)

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, :job_conflict} -> {:ok, :busy}
      error -> error
    end
  end

  defp reconcile(key, scope_type, scope_id) do
    from(r in DailyRun,
      where: r.task_key == ^key and r.scope_type == ^scope_type and r.scope_id == ^scope_id,
      where: r.status in ["scheduled", "running", "retrying", "snoozed"]
    )
    |> Repo.all()
    |> Enum.each(fn run ->
      state = if run.job_id, do: Repo.get(Oban.Job, run.job_id) |> then(&(&1 && &1.state))

      attrs =
        case state do
          "completed" ->
            %{status: "completed", finished_at: DateTime.utc_now(), last_error: nil}

          state when state in ["discarded", "cancelled", nil] ->
            %{
              status: "failed",
              finished_at: DateTime.utc_now(),
              last_error: "Oban job #{state || "missing"}"
            }

          state when state in ["available", "retryable"] and run.status == "running" ->
            %{status: "retrying"}

          _ ->
            nil
        end

      if attrs do
        run
        |> Ecto.Changeset.change(attrs)
        |> Repo.update!()
      end
    end)
  end

  defp run_exists?(key, scope_type, scope_id, date) do
    Repo.exists?(
      from(r in DailyRun,
        where:
          r.task_key == ^key and r.scope_type == ^scope_type and
            r.scope_id == ^scope_id and r.local_date == ^date
      )
    )
  end

  defp active_job?(key, scope_type, scope_id) do
    worker = Oban.Worker.to_string(DailyJob)

    Repo.exists?(
      from(j in Oban.Job,
        where: j.worker == ^worker and j.state in ^@active_states,
        where: fragment("?->>'task_key' = ?", j.args, ^key),
        where: fragment("?->>'scope_type' = ?", j.args, ^scope_type),
        where: fragment("?->>'scope_id' = ?", j.args, ^scope_id)
      )
    )
  end
end
