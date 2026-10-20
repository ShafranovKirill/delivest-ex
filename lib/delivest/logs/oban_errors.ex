defmodule Delivest.Logs.ObanErrors do
  require Logger

  @handler_id "delivest-oban-errors"

  def attach do
    :telemetry.attach(@handler_id, [:oban, :job, :exception], &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, _measurements, %{job: job, kind: kind, reason: reason}, _config) do
    Logger.error(
      "job #{job.worker} failed (attempt #{job.attempt}/#{job.max_attempts}): " <>
        Exception.format_banner(kind, reason),
      worker: job.worker,
      job_id: job.id
    )
  end
end
