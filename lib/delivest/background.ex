defmodule Delivest.Background do
  @moduledoc "Shared, bounded dispatcher for optional feature calculations."
  import Ecto.Query
  alias Delivest.{Features, Repo}
  alias Delivest.Background.{Dispatcher, Registry, Runner, Schedule}
  alias Delivest.Features.Gate

  @batch_size 10
  @critical_queues ~w(default notifications polling rkeeper_polling crm events payments fiscal)

  def feature_changed(feature, scope, enabled) do
    if not enabled do
      Registry.feature_disabled(feature, scope)
      Delivest.Notifications.SourceRegistry.feature_disabled(feature, scope)
    end

    Enum.each(Registry.tasks_for_feature(feature), fn {kind, task} ->
      cond do
        scope == task.scope and enabled ->
          schedule(kind, scope)

        scope == task.scope ->
          unschedule(kind, scope)

        match?({:branch, _}, scope) and task.scope == :franchise and
            Features.enabled?(feature, :franchise) ->
          invalidate(kind, :franchise)

        true ->
          :ok
      end
    end)

    :ok
  end

  def invalidate(kind, scope) do
    with {:ok, task} <- Registry.fetch(kind),
         true <- task.scope == scope,
         {:ok, key} <- Features.scope_key(scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.update_all(from(s in Schedule, where: s.kind == ^kind and s.scope_key == ^key),
        set: [running: false, current_job_id: nil, next_at: now]
      )

      cancel_pending(kind, key)
      :ok
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  @doc "Wake the shared dispatcher for an interactive request; the periodic dispatcher remains the fallback."
  def kick do
    Dispatcher.new(%{},
      unique: [period: 30, fields: [:worker, :args], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  def schedule(kind, scope) do
    with {:ok, task} <- Registry.fetch(kind),
         true <- task.scope == scope,
         {:ok, key} <- Features.scope_key(scope),
         true <- Features.enabled?(task.feature, scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.insert_all(
        Schedule,
        [%{kind: kind, scope_key: key, next_at: now, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: [:kind, :scope_key]
      )

      :ok
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  def unschedule(kind, scope) do
    with {:ok, task} <- Registry.fetch(kind),
         true <- task.scope == scope,
         {:ok, key} <- Features.scope_key(scope) do
      Repo.delete_all(from s in Schedule, where: s.kind == ^kind and s.scope_key == ^key)
      cancel_pending(kind, key)
      :ok
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  def still_enabled?(%{feature: feature, scope: scope, generation: token} = context),
    do: Features.still_enabled?(feature, scope, token) and owner?(context)

  def checkpoint(context) do
    cond do
      not still_enabled?(context) -> {:error, :disabled}
      pressure_high?() -> {:snooze, 300}
      true -> :ok
    end
  end

  def publish(%{feature: feature, scope: scope, generation: token} = context, fun),
    do:
      Features.with_enabled(feature, scope, token, fn ->
        assert_owner!(context)
        fun.()
      end)

  def publish(context, scope, token, fun),
    do: publish(context, scope, token, [], fun)

  @doc "Publish a branch result with its original planner epoch and owner still fenced."
  def publish(
        %{feature: feature, scope: original_scope, generation: original} = context,
        scope,
        %{franchise: franchise} = token,
        extra,
        fun
      )
      when is_list(extra) and is_function(fun, 0) do
    if franchise != original.franchise do
      {:error, :disabled}
    else
      Features.with_enabled_many(
        [{feature, original_scope, original}, {feature, scope, token} | extra],
        fn ->
          assert_owner!(context)
          fun.()
        end
      )
    end
  end

  def owner?(%{schedule_id: schedule_id, job_id: job_id})
      when is_integer(schedule_id) and is_integer(job_id) do
    Repo.exists?(
      from s in Schedule,
        where: s.id == ^schedule_id and s.current_job_id == ^job_id and s.running
    )
  end

  def owner?(_), do: false

  defp assert_owner!(%{schedule_id: schedule_id, job_id: job_id})
       when is_integer(schedule_id) and is_integer(job_id) do
    owner = Repo.one(from s in Schedule, where: s.id == ^schedule_id, lock: "FOR UPDATE")

    if not (owner && owner.current_job_id == job_id && owner.running),
      do: Repo.rollback(:disabled)
  end

  defp assert_owner!(_), do: Repo.rollback(:disabled)

  def overdue_count do
    Repo.aggregate(from(s in Schedule, where: s.next_at <= ^DateTime.utc_now()), :count)
  end

  def status do
    now = DateTime.utc_now()

    Repo.all(
      from s in Schedule,
        select: %{
          kind: s.kind,
          scope_key: s.scope_key,
          next_at: s.next_at,
          running: s.running,
          last_success_at: s.last_success_at,
          last_error_at: s.last_error_at,
          last_error: s.last_error,
          overdue: s.next_at < ^now
        },
        order_by: s.next_at
    )
  end

  def dispatch_due do
    if pressure?() do
      {:deferred, :critical_backlog}
    else
      Repo.transaction(fn ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        recover_terminal_runs()

        rows =
          Repo.all(
            from s in Schedule,
              where: s.next_at <= ^now and not s.running,
              order_by: s.next_at,
              limit: @batch_size,
              lock: "FOR UPDATE SKIP LOCKED"
          )

        Enum.reduce(rows, 0, fn row, count ->
          scope = Features.parse_scope(row.scope_key)

          case Registry.fetch(row.kind) do
            {:ok, task} ->
              case Features.snapshot(task.feature, scope) do
                {:ok, token} ->
                  args = %{
                    kind: row.kind,
                    scope_key: row.scope_key,
                    generation: token,
                    schedule_id: row.id
                  }

                  {:ok, job} = Oban.insert(Runner.new(args))

                  row
                  |> Ecto.Changeset.change(running: true, current_job_id: job.id)
                  |> Repo.update!()

                  count + 1

                _ ->
                  Repo.delete!(row)
                  count
              end

            :error ->
              Repo.delete!(row)
              count
          end
        end)
      end)
    end
  end

  @doc "Restore missing schedules after a database swap using the preserved host gates."
  def reconcile do
    Enum.each(Registry.all(), fn {kind, task} ->
      if task.scope == :franchise do
        {:ok, _} =
          Repo.transaction(fn ->
            gate =
              Repo.one(
                from g in Gate,
                  where: g.feature == ^task.feature and g.scope_key == "franchise",
                  lock: "FOR UPDATE"
              )

            cond do
              gate && gate.enabled ->
                schedule(kind, :franchise)

              Repo.exists?(
                from s in Schedule,
                  where: s.kind == ^kind and s.scope_key == "franchise"
              ) ->
                unschedule(kind, :franchise)

              true ->
                :ok
            end
          end)
      end
    end)

    :ok
  end

  def finish(kind, scope_key, job_id, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    {:ok, task} = Registry.fetch(kind)
    next_at = DateTime.add(now, task.interval, :second)

    updates =
      if result == :ok,
        do: [
          running: false,
          current_job_id: nil,
          next_at: next_at,
          last_success_at: now,
          last_error: nil
        ],
        else: [
          running: false,
          current_job_id: nil,
          next_at: next_at,
          last_error_at: now,
          last_error: "background calculation failed"
        ]

    Repo.update_all(
      from(s in Schedule,
        where: s.kind == ^kind and s.scope_key == ^scope_key and s.current_job_id == ^job_id
      ),
      set: updates
    )

    :ok
  end

  def record_error(kind, scope_key, job_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in Schedule,
        where: s.kind == ^kind and s.scope_key == ^scope_key and s.current_job_id == ^job_id
      ),
      set: [last_error_at: now, last_error: "background calculation failed"]
    )

    :ok
  end

  def pressure_high?, do: pressure?()

  defp recover_terminal_runs do
    stale =
      Repo.all(
        from s in Schedule,
          left_join: j in Oban.Job,
          on: j.id == s.current_job_id,
          where:
            s.running and (is_nil(j.id) or j.state in ["completed", "cancelled", "discarded"]),
          order_by: s.next_at,
          limit: @batch_size,
          lock: "FOR UPDATE OF b0 SKIP LOCKED",
          select: {s.id, s.kind, s.current_job_id}
      )

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Enum.each(stale, fn {id, kind, observed_job_id} ->
      query =
        from s in Schedule,
          where: s.id == ^id and s.running and s.current_job_id == ^observed_job_id

      case Registry.fetch(kind) do
        {:ok, task} ->
          Repo.update_all(query,
            set: [
              running: false,
              current_job_id: nil,
              next_at: DateTime.add(now, task.interval, :second),
              last_error_at: now,
              last_error: "background calculation terminated before completion"
            ]
          )

        :error ->
          Repo.delete_all(query)
      end
    end)
  end

  defp pressure? do
    limit = Application.get_env(:delivest, :background_pressure_limit, 50)
    now = DateTime.utc_now()

    query =
      from j in Oban.Job,
        where:
          j.queue in ^@critical_queues and
            (j.state == "executing" or
               (j.state in ["available", "retryable"] and j.scheduled_at <= ^now)),
        limit: ^max(limit, 1),
        select: j.id

    Repo.aggregate(subquery(query), :count) >= limit
  end

  defp cancel_pending(kind, scope_key) do
    query =
      from j in Oban.Job,
        where:
          j.worker == "Delivest.Background.Runner" and
            j.state in ["available", "scheduled", "retryable"] and
            fragment("?->>'kind'", j.args) == ^kind and
            fragment("?->>'scope_key'", j.args) == ^scope_key

    Oban.cancel_all_jobs(query)
  end
end
