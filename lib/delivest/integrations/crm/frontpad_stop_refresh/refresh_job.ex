defmodule Delivest.Integrations.Crm.FrontpadStopRefresh.RefreshJob do
  use Oban.Worker,
    queue: :polling,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable],
      fields: [:args],
      keys: [:branch_id]
    ]

  alias Delivest.Integrations.Availability
  alias Delivest.Integrations.Crm.{FrontpadStopRefresh, StopSync}

  @impl Oban.Worker
  def backoff(_job), do: 60

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id} = args} = job) do
    if FrontpadStopRefresh.eligible?(branch_id) and
         is_integer(args["generation"]) and
         Availability.crm_allowed?(branch_id, :frontpad, :stops, args["generation"]) do
      FrontpadStopRefresh.put_state(branch_id, %{
        job_id: job.id,
        status: "running",
        last_attempt_at: DateTime.utc_now(),
        last_error: nil
      })

      FrontpadStopRefresh.broadcast(branch_id)

      case StopSync.sync_generation(branch_id, args["generation"]) do
        {:ok, %{stopped: count, unlinked: unlinked}} ->
          FrontpadStopRefresh.put_state(branch_id, %{
            status: "success",
            last_success_at: DateTime.utc_now(),
            last_good_count: count,
            last_good_unlinked: unlinked,
            last_error: nil
          })

          FrontpadStopRefresh.broadcast(branch_id)
          :ok

        {:ok, :disabled} ->
          disabled(branch_id)

        {:error, :settings_changed} ->
          disabled(branch_id)

        {:error, _reason} ->
          failed(branch_id, job)
      end
    else
      disabled(branch_id)
    end
  rescue
    _error -> failed(branch_id, job)
  end

  defp disabled(branch_id) do
    FrontpadStopRefresh.put_state(branch_id, %{status: "disabled", last_error: nil})
    FrontpadStopRefresh.broadcast(branch_id)
    :ok
  end

  defp failed(branch_id, job) do
    terminal? = job.attempt >= job.max_attempts

    FrontpadStopRefresh.put_state(branch_id, %{
      status: if(terminal?, do: "failed", else: "retrying"),
      last_error: "Frontpad did not respond. Try again later."
    })

    FrontpadStopRefresh.broadcast(branch_id)
    {:error, :frontpad_stop_refresh_failed}
  end
end
