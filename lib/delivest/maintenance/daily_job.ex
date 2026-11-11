defmodule Delivest.Maintenance.DailyJob do
  @moduledoc "Runs a registered daily task while keeping its durable run state."

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [
      period: 2_592_000,
      states: [:available, :scheduled, :executing, :retryable],
      fields: [:args],
      keys: [:task_key, :scope_type, :scope_id]
    ]

  import Ecto.Query

  alias Delivest.Maintenance.{DailyRun, Registry}
  alias Delivest.Repo

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"task_key" => key}}) do
    case Registry.task(key) do
      nil ->
        Registry.max_timeout_ms()

      task ->
        case Registry.validate(task) do
          :ok -> Registry.timeout_ms(task)
          {:error, _} -> Registry.max_timeout_ms()
        end
    end
  end

  def timeout(_job), do: Registry.max_timeout_ms()

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "task_key" => key,
            "scope_type" => type,
            "scope_id" => scope_id,
            "run_id" => run_id
          }
        } = job
      ) do
    job_id = job.id

    with {:ok, task} <- Registry.resolve(key, type),
         %DailyRun{
           job_id: ^job_id,
           task_key: ^key,
           scope_type: ^type,
           scope_id: ^scope_id
         } = run <- Repo.get(DailyRun, run_id) do
      if run.status == "completed" do
        :ok
      else
        update_run(run_id, %{status: "running", started_at: DateTime.utc_now()})

        try do
          result = task.worker.perform(job)
          record_result(run_id, job, result)
          result
        rescue
          error ->
            record_error(run_id, job, Exception.message(error))
            reraise error, __STACKTRACE__
        catch
          kind, reason ->
            record_error(run_id, job, inspect(reason))
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
      end
    else
      _ -> {:error, :unknown_daily_run}
    end
  end

  defp record_result(run_id, _job, :ok), do: complete(run_id)
  defp record_result(run_id, _job, {:ok, _}), do: complete(run_id)
  defp record_result(run_id, _job, {:snooze, _}), do: update_run(run_id, %{status: "snoozed"})

  defp record_result(run_id, _job, {:cancel, reason}) do
    update_run(run_id, %{
      status: "failed",
      finished_at: DateTime.utc_now(),
      last_error: inspect(reason)
    })
  end

  defp record_result(run_id, job, {:error, reason}),
    do: record_error(run_id, job, inspect(reason))

  defp record_result(run_id, job, other),
    do: record_error(run_id, job, "unexpected result: #{inspect(other)}")

  defp complete(run_id),
    do:
      update_run(run_id, %{status: "completed", finished_at: DateTime.utc_now(), last_error: nil})

  defp record_error(run_id, job, reason) do
    terminal? = job.attempt >= job.max_attempts

    update_run(run_id, %{
      status: if(terminal?, do: "failed", else: "retrying"),
      finished_at: if(terminal?, do: DateTime.utc_now()),
      last_error: String.slice(reason, 0, 2000)
    })
  end

  defp update_run(id, attrs) do
    from(r in DailyRun, where: r.id == ^id)
    |> Repo.update_all(set: Map.to_list(attrs) ++ [updated_at: DateTime.utc_now()])

    :ok
  end
end
