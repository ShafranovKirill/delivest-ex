defmodule Delivest.Background.Runner do
  use Oban.Worker, queue: :background, max_attempts: 3

  alias Delivest.{Background, Features}
  alias Delivest.Background.Registry
  alias Delivest.Repo

  @impl Oban.Worker
  def timeout(%Oban.Job{args: %{"kind" => kind}}) do
    case Registry.fetch(kind) do
      {:ok, task} -> Application.get_env(:delivest, :background_task_timeout_ms, task.timeout)
      :error -> :timer.minutes(1)
    end
  end

  def timeout(_job), do: :timer.minutes(1)

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "kind" => kind,
          "scope_key" => key,
          "generation" => raw,
          "schedule_id" => schedule_id
        }
      }) do
    with {:ok, task} <- Registry.fetch(kind) do
      token = %{franchise: raw["franchise"], branch: raw["branch"]}
      scope = Features.parse_scope(key)

      context = %{
        feature: task.feature,
        scope: scope,
        generation: token,
        schedule_id: schedule_id,
        job_id: job_id
      }

      case Background.checkpoint(context) do
        :ok -> run(task, scope, context, kind, key, job_id)
        {:snooze, seconds} -> {:snooze, seconds}
        {:error, :disabled} -> {:cancel, :disabled}
      end
    else
      :error -> {:cancel, :unknown_background_task}
    end
  end

  def perform(_), do: {:cancel, :unknown_background_task}

  defp run(task, scope, context, kind, key, job_id) do
    try do
      result =
        Repo.checkout(
          fn ->
            [[previous]] = Repo.query!("SHOW statement_timeout").rows

            Repo.query!(
              "SELECT set_config('statement_timeout', $1, false)",
              [Integer.to_string(task.statement_timeout)],
              timeout: task.statement_timeout + 5_000
            )

            try do
              task.handler.perform(scope, context)
            after
              Repo.query!("SELECT set_config('statement_timeout', $1, false)", [previous])
            end
          end,
          timeout: task.timeout + 5_000
        )

      case result do
        :ok ->
          Background.finish(kind, key, job_id, :ok)

        {:snooze, seconds} ->
          {:snooze, seconds}

        {:error, :disabled} ->
          {:cancel, :disabled}

        {:error, _reason} ->
          Background.record_error(kind, key, job_id)
          raise "background calculation failed"

        _other ->
          Background.record_error(kind, key, job_id)
          raise "unexpected background result"
      end
    rescue
      error ->
        Background.record_error(kind, key, job_id)
        reraise error, __STACKTRACE__
    end
  end
end
