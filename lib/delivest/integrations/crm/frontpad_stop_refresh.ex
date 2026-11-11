defmodule Delivest.Integrations.Crm.FrontpadStopRefresh do
  @moduledoc "Durable, branch-scoped requests for a Frontpad stop-list refresh."

  import Ecto.Query

  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Crm.FrontpadStopRefresh.{RefreshJob, State}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Repo

  @active_states ~w(available scheduled executing retryable)
  @cooldown_seconds 60
  @pending_statuses ~w(queued running retrying)

  def topic(branch_id), do: "frontpad_stop_refresh:#{branch_id}"

  def state(branch_id) do
    case Repo.get(State, branch_id) do
      %State{status: status} = current when status in @pending_statuses ->
        reconcile(current)

      current ->
        current
    end
  end

  defp reconcile(%State{job_id: job_id} = current) do
    job = job_id && Repo.get(Oban.Job, job_id)

    attrs =
      case job do
        %Oban.Job{state: "retryable"} when current.status != "retrying" ->
          %{status: "retrying", last_error: "Обновление не завершилось. Ожидается повтор."}

        %Oban.Job{state: state} when state in ["discarded", "cancelled", "completed"] ->
          %{status: "failed", last_error: "Обновление не завершилось. Попробуйте снова."}

        nil ->
          %{status: "failed", last_error: "Задача обновления не найдена. Попробуйте снова."}

        _ ->
          nil
      end

    if attrs do
      from(s in State,
        where: s.branch_id == ^current.branch_id,
        where: s.status in ^@pending_statuses and s.updated_at == ^current.updated_at
      )
      |> Repo.update_all(set: Map.to_list(attrs) ++ [updated_at: DateTime.utc_now()])

      Repo.get!(State, current.branch_id)
    else
      current
    end
  end

  def eligible?(branch_id) do
    case Repo.get(Branch, branch_id) do
      %Branch{is_active: true, deleted_at: nil} ->
        settings = Crm.get_branch_settings(branch_id)

        BranchSettings.active_provider(settings) == :frontpad and
          Frontpad.stops_enabled?(settings.frontpad)

      _ ->
        false
    end
  end

  def request(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "integrations.update", branch_id) do
      request_internal(branch_id, :manual)
    end
  end

  def request_internal(branch_id, reason) when reason in [:manual, :daily, :product_rejected] do
    if eligible?(branch_id) do
      do_request(branch_id)
    else
      {:ok, :disabled}
    end
  end

  defp do_request(branch_id) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "frontpad_stops:#{branch_id}"
      ])

      current = state(branch_id)
      active = active_job(branch_id)

      cond do
        active && current && current.job_id == active.id &&
            current.status in ["success", "failed", "disabled"] ->
          {:ok, :throttled}

        active ->
          {:ok, :coalesced}

        current && current.last_attempt_at &&
            DateTime.diff(DateTime.utc_now(), current.last_attempt_at, :second) <
              @cooldown_seconds ->
          {:ok, :throttled}

        true ->
          case %{branch_id: branch_id} |> RefreshJob.new() |> Oban.insert() do
            {:ok, %Oban.Job{} = job} ->
              put_state(branch_id, %{status: "queued", job_id: job.id, last_error: nil})
              {:ok, :queued}

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, {:ok, :queued} = result} ->
        broadcast(branch_id)
        result

      {:ok, result} ->
        result

      error ->
        error
    end
  end

  defp active_job(branch_id) do
    worker = Oban.Worker.to_string(RefreshJob)

    from(j in Oban.Job,
      where: j.worker == ^worker and j.state in ^@active_states,
      where: fragment("?->>'branch_id' = ?", j.args, ^branch_id),
      order_by: [desc: j.id],
      limit: 1
    )
    |> Repo.one()
  end

  def put_state(branch_id, attrs) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct(State, Map.merge(%{branch_id: branch_id, inserted_at: now, updated_at: now}, attrs)),
      on_conflict: [set: Map.to_list(attrs) ++ [updated_at: now]],
      conflict_target: :branch_id
    )
  end

  def broadcast(branch_id) do
    Phoenix.PubSub.broadcast(
      Delivest.PubSub,
      topic(branch_id),
      {:frontpad_stop_refresh, state(branch_id)}
    )
  end
end
