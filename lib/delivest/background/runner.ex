defmodule Delivest.Background.Runner do
  use Oban.Worker, queue: :background, max_attempts: 3

  alias Delivest.{Background, Features}
  alias Delivest.Background.Registry

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"kind" => kind, "scope_key" => key, "generation" => raw}
      }) do
    with {:ok, task} <- Registry.fetch(kind) do
      token = %{franchise: raw["franchise"], branch: raw["branch"]}
      scope = Features.parse_scope(key)

      context = %{
        feature: task.feature,
        scope: scope,
        generation: token,
        schedule_id: raw["schedule_id"],
        job_id: job_id
      }

      cond do
        not Background.still_enabled?(context) -> :ok
        Background.pressure_high?() -> {:snooze, 300}
        true -> run(task.handler, scope, context, kind, key, job_id)
      end
    else
      :error -> {:cancel, :unknown_background_task}
    end
  end

  def perform(_), do: {:cancel, :unknown_background_task}

  defp run(handler, scope, context, kind, key, job_id) do
    try do
      case handler.perform(scope, context) do
        :ok ->
          Background.finish(kind, key, job_id, :ok)

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
