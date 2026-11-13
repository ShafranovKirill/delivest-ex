defmodule Delivest.Background do
  @moduledoc "Shared, bounded dispatcher for optional feature calculations."
  import Ecto.Query
  alias Delivest.{Availability, Features, Repo}
  alias Delivest.Background.{DailySchedule, Dispatcher, Registry, Runner, Schedule}
  alias Delivest.Features.Gate

  @batch_size 10
  @critical_queues ~w(default notifications polling rkeeper_polling crm events payments fiscal)

  @doc "Coalesce an interactive calculation into the existing scheduled runner."
  def run_now(kind, scope, opts \\ [])

  def run_now(kind, scope, opts) when is_list(opts) do
    with {:ok, %{manual?: true} = task} <- Registry.fetch(kind),
         true <- matching_scope?(task.scope, scope),
         {:ok, key} <- Features.scope_key(scope),
         {:ok, token} <- Availability.feature_snapshot(task.feature, scope) do
      result =
        Features.with_enabled(task.feature, scope, token, fn ->
          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
          daily? = daily?(task)
          date = if daily?, do: DailySchedule.latest_due_date(now, DailySchedule.zone(key))

          Repo.insert_all(
            Schedule,
            [
              %{
                kind: kind,
                scope_key: key,
                next_at: now,
                daily_date: date,
                manual_requested: daily?,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:kind, :scope_key]
          )

          row =
            Repo.one!(
              from s in Schedule,
                where: s.kind == ^kind and s.scope_key == ^key,
                lock: "FOR UPDATE"
            )

          owner_job = if row.running, do: owner_job(row.current_job_id)

          cond do
            row.running and terminal_owner?(owner_job) ->
              row
              |> Ecto.Changeset.change(
                running: false,
                current_job_id: nil,
                rerun_requested: false,
                next_at: now,
                manual_requested: daily?,
                daily_date: date
              )
              |> Repo.update!()

              :queued

            row.running ->
              if Keyword.get(opts, :new_work, false) and not row.rerun_requested do
                row |> Ecto.Changeset.change(rerun_requested: true) |> Repo.update!()
              end

              if owner_job.state in ["scheduled", "retryable"] do
                :ok = Oban.retry_job(owner_job.id)
                :queued
              else
                if owner_job.state == "executing", do: :running, else: :queued
              end

            true ->
              row
              |> Ecto.Changeset.change(
                next_at: now,
                rerun_requested: false,
                manual_requested: daily?,
                daily_date: date
              )
              |> Repo.update!()

              :queued
          end
        end)

      case result do
        {:ok, :queued} ->
          kick()
          {:ok, :queued}

        {:ok, :running} ->
          {:ok, :running}

        error ->
          error
      end
    else
      {:error, :disabled} -> {:error, :disabled}
      _ -> {:error, :invalid_schedule}
    end
  end

  def run_now(_, _, _), do: {:error, :invalid_schedule}

  def feature_changed(feature, scope, enabled) do
    if not enabled do
      Registry.feature_disabled(feature, scope)
      Delivest.Notifications.SourceRegistry.feature_disabled(feature, scope)
    end

    Enum.each(Registry.tasks_for_feature(feature), fn {kind, task} ->
      cond do
        matching_scope?(task.scope, scope) and enabled ->
          schedule(kind, scope)

        matching_scope?(task.scope, scope) ->
          unschedule(kind, scope)

        scope == :franchise and task.scope == :branch and not enabled ->
          unschedule_branches(kind)

        match?({:branch, _}, scope) and task.scope == :franchise and
            Availability.feature_enabled?(feature, :franchise) ->
          invalidate(kind, :franchise)

        true ->
          :ok
      end
    end)

    :ok
  end

  def invalidate(kind, scope) do
    with {:ok, task} <- Registry.fetch(kind),
         true <- matching_scope?(task.scope, scope),
         {:ok, key} <- Features.scope_key(scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      {date, next_at} = initial_next(task, key, now)

      Repo.update_all(from(s in Schedule, where: s.kind == ^kind and s.scope_key == ^key),
        set: [
          running: false,
          current_job_id: nil,
          rerun_requested: false,
          manual_requested: false,
          daily_date: date,
          next_at: next_at
        ]
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
         true <- matching_scope?(task.scope, scope),
         {:ok, key} <- Features.scope_key(scope),
         true <- Availability.feature_enabled?(task.feature, scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      {date, next_at} = initial_next(task, key, now)

      Repo.insert_all(
        Schedule,
        [
          %{
            kind: kind,
            scope_key: key,
            next_at: next_at,
            daily_date: date,
            inserted_at: now,
            updated_at: now
          }
        ],
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
         true <- matching_scope?(task.scope, scope),
         {:ok, key} <- Features.scope_key(scope) do
      Repo.delete_all(from s in Schedule, where: s.kind == ^kind and s.scope_key == ^key)
      cancel_pending(kind, key)
      :ok
    else
      _ -> {:error, :invalid_schedule}
    end
  end

  def still_enabled?(%{feature: feature, scope: scope, generation: token} = context),
    do: Availability.feature_still_enabled?(feature, scope, token) and owner?(context)

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

  @doc "Read calculation state without creating a schedule or job."
  def calculation_status(kind, scope) do
    with {:ok, %{manual?: true} = task} <- Registry.fetch(kind),
         true <- matching_scope?(task.scope, scope),
         {:ok, key} <- Features.scope_key(scope),
         {:ok, _} <- Availability.feature_snapshot(task.feature, scope) do
      row = Repo.one(from s in Schedule, where: s.kind == ^kind and s.scope_key == ^key)
      now = DateTime.utc_now()

      state =
        cond do
          row == nil ->
            :queued

          row.running ->
            job_state(row.current_job_id)

          DateTime.compare(row.next_at, now) != :gt ->
            :queued

          row.last_error_at &&
              (is_nil(row.last_success_at) or
                 DateTime.compare(row.last_error_at, row.last_success_at) == :gt) ->
            :error

          row.last_success_at ->
            :ready

          true ->
            :queued
        end

      {:ok,
       %{
         state: state,
         last_success_at: if(row, do: row.last_success_at),
         last_error: if(row, do: row.last_error)
       }}
    else
      _ -> {:error, :disabled}
    end
  end

  defp job_state(nil), do: :queued

  defp job_state(job_id) do
    case Repo.get(Oban.Job, job_id) do
      %{state: "executing"} -> :running
      _ -> :queued
    end
  end

  defp matching_scope?(:branch, {:branch, id}) when is_binary(id), do: true
  defp matching_scope?(configured, scope), do: configured == scope

  defp owner_job(nil), do: nil
  defp owner_job(job_id), do: Repo.get(Oban.Job, job_id)

  defp terminal_owner?(nil), do: true
  defp terminal_owner?(%{state: state}), do: state in ["completed", "cancelled", "discarded"]

  def dispatch_due do
    if pressure?() do
      {:deferred, :critical_backlog}
    else
      Repo.transaction(fn ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        recover_terminal_runs(now)
        normalize_daily(now)

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
              case Availability.feature_snapshot(task.feature, scope) do
                {:ok, token} ->
                  args = %{
                    kind: row.kind,
                    scope_key: row.scope_key,
                    generation: token,
                    schedule_id: row.id
                  }

                  {:ok, job} = Oban.insert(Runner.new(args))

                  date =
                    if row.manual_requested and daily?(task),
                      do: DailySchedule.latest_due_date(now, DailySchedule.zone(row.scope_key)),
                      else: row.daily_date

                  row
                  |> Ecto.Changeset.change(
                    running: true,
                    current_job_id: job.id,
                    manual_requested: false,
                    daily_date: date
                  )
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

      if task.scope == :branch do
        reconcile_branches(kind, task.feature)
      end
    end)

    :ok
  end

  defp unschedule_branches(kind) do
    Repo.delete_all(from s in Schedule, where: s.kind == ^kind and like(s.scope_key, "branch:%"))

    Repo.query!(
      """
      UPDATE oban_jobs SET state='cancelled',cancelled_at=now()
      WHERE worker LIKE '%Background.Runner' AND args->>'kind'=$1 AND args->>'scope_key' LIKE 'branch:%'
        AND state IN ('available','scheduled','retryable')
      """,
      [kind]
    )

    :ok
  end

  defp reconcile_branches(kind, feature) do
    ids =
      Repo.query!(
        """
        SELECT b.id::text FROM branches b
        JOIN feature_gates g ON g.scope_key='branch:' || b.id::text
          AND g.feature=$1 AND g.enabled
        JOIN feature_gates parent ON parent.feature=g.feature AND parent.scope_key='franchise' AND parent.enabled
        LEFT JOIN background_schedules s ON s.scope_key=g.scope_key AND s.kind=$2
        WHERE b.deleted_at IS NULL AND s.id IS NULL
        ORDER BY b.id LIMIT 10
        """,
        [feature, kind]
      ).rows

    Enum.each(ids, fn [id] -> schedule(kind, {:branch, id}) end)
  end

  def finish(kind, scope_key, job_id, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    {:ok, task} = Registry.fetch(kind)

    {:ok, rerun?} =
      Repo.transaction(fn ->
        row =
          Repo.one(
            from s in Schedule,
              where:
                s.kind == ^kind and s.scope_key == ^scope_key and s.current_job_id == ^job_id,
              lock: "FOR UPDATE"
          )

        if row do
          {date, next_at} = next_after_run(task, row, now)

          updates = [
            running: false,
            current_job_id: nil,
            rerun_requested: false,
            manual_requested: row.rerun_requested and daily?(task),
            daily_date: date,
            next_at: if(row.rerun_requested, do: now, else: next_at)
          ]

          updates =
            if result == :ok,
              do: updates ++ [last_success_at: now, last_error: nil],
              else: updates ++ [last_error_at: now, last_error: "background calculation failed"]

          row |> Ecto.Changeset.change(updates) |> Repo.update!()
          row.rerun_requested
        else
          false
        end
      end)

    if rerun?, do: kick()

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

  defp recover_terminal_runs(now) do
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
          select: {s.id, s.kind, s.scope_key, s.current_job_id, s.rerun_requested, s.daily_date}
      )

    Enum.each(stale, fn {id, kind, key, observed_job_id, rerun?, date} ->
      query =
        from s in Schedule,
          where: s.id == ^id and s.running and s.current_job_id == ^observed_job_id

      case Registry.fetch(kind) do
        {:ok, task} ->
          {next_date, next_at} = next_after_run(task, %{scope_key: key, daily_date: date}, now)

          Repo.update_all(query,
            set: [
              running: false,
              current_job_id: nil,
              rerun_requested: false,
              manual_requested: rerun? and daily?(task),
              daily_date: next_date,
              next_at: if(rerun?, do: now, else: next_at),
              last_error_at: now,
              last_error: "background calculation terminated before completion"
            ]
          )

        :error ->
          Repo.delete_all(query)
      end
    end)
  end

  defp daily?(task), do: Map.get(task, :schedule) == :daily_03

  defp initial_next(task, key, now) do
    if daily?(task),
      do: DailySchedule.next_future(now, DailySchedule.zone(key)),
      else: {nil, now}
  end

  defp next_after_run(task, row, now) do
    if daily?(task) do
      zone = DailySchedule.zone(row.scope_key)

      if row.daily_date,
        do: DailySchedule.next_after(row.daily_date, now, zone),
        else: DailySchedule.next_future(now, zone)
    else
      {nil, DateTime.add(now, task.interval, :second)}
    end
  end

  defp normalize_daily(now) do
    kinds = for {kind, task} <- Registry.all(), daily?(task), do: kind

    Repo.all(
      from s in Schedule,
        where: s.kind in ^kinds and not s.running and not s.manual_requested,
        lock: "FOR UPDATE SKIP LOCKED"
    )
    |> Enum.each(fn row ->
      {date, next_at} = DailySchedule.normalize(row, now, DailySchedule.zone(row.scope_key))

      if row.daily_date != date or DateTime.compare(row.next_at, next_at) != :eq do
        row |> Ecto.Changeset.change(daily_date: date, next_at: next_at) |> Repo.update!()
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
