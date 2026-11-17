defmodule Delivest.Analytics.Reports.Refresh do
  @moduledoc "Refresh one dirty branch/day bucket through the shared background runner."
  alias Delivest.{Background, Features, LocalTime, Repo}
  alias Delivest.Analytics.Reports.Calculator

  @customer_batch 500
  @link_batch 500
  @days_per_run 2
  @zero "00000000-0000-0000-0000-000000000000"

  def perform({:branch, branch_id}, %{feature: feature} = context)
      when feature in ["analytics_funnel", "analytics_links", "analytics_extended"] do
    with_lock(feature, branch_id, fn ->
      with :ok <- checkpoint(context) do
        day = LocalTime.today(LocalTime.timezone(branch_id))
        ensure_collected_days(feature, branch_id, Date.add(day, -1), day)
        finalize_closed_days(feature, branch_id, day)
        result = refresh_pending(feature, branch_id, day, context)

        if result == :ok and pending_day(feature, branch_id, day, []) != nil do
          Background.run_now(kind(feature), {:branch, branch_id}, new_work: true)
        end

        result
      end
    end)
  end

  def perform(_, _), do: {:error, :invalid_scope}

  @doc "Refresh only requested dirty buckets within a shared small entry budget."
  def on_read(feature, ids, {from, to}, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :budget_ms, 1_500)
    limit = Keyword.get(opts, :bucket_limit, 4)

    enabled = Features.enabled_branches(feature, ids)
    ids = Enum.filter(ids, &MapSet.member?(enabled, &1))
    ensure_collected_days(feature, ids, from, to)
    candidates = pending_branches(feature, ids, from, to)

    {_remaining, pending_ids} =
      Enum.reduce(candidates, {limit, []}, fn id, {remaining, pending_ids} ->
        scope = {:branch, id}

        if remaining > 0 and System.monotonic_time(:millisecond) < deadline do
          case Features.snapshot(feature, scope) do
            {:ok, generation} ->
              context = %{
                feature: feature,
                scope: scope,
                generation: generation,
                deadline: deadline
              }

              result =
                with_lock(feature, id, fn ->
                  refresh_requested(feature, id, from, to, context, remaining)
                end)

              case result do
                {used, false} -> {remaining - used, pending_ids}
                {used, true} -> {remaining - used, [id | pending_ids]}
                _ -> {remaining, [id | pending_ids]}
              end

            _ ->
              {remaining, pending_ids}
          end
        else
          {remaining, [id | pending_ids]}
        end
      end)

    if pending_ids != [], do: enqueue_pending(feature, pending_ids)
    pending_ids != []
  end

  defp pending_branches(_feature, [], _from, _to), do: []

  defp pending_branches(feature, ids, from, to) do
    Repo.query!(
      """
      SELECT DISTINCT s.branch_id::text FROM analytics_report_states s
      LEFT JOIN analytics_report_snapshots p ON p.id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
        AND (s.snapshot_id IS NULL OR s.revision>p.revision)
      ORDER BY s.branch_id::text
      """,
      [feature, Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
    ).rows
    |> Enum.map(&hd/1)
  end

  defp enqueue_pending(feature, ids) do
    ids
    |> Enum.take(4)
    |> Enum.each(&Background.run_now(kind(feature), {:branch, &1}, new_work: true))
  end

  defp refresh_requested(feature, id, from, to, context, remaining, used \\ 0) do
    case requested_day(feature, id, from, to) do
      nil ->
        {used, false}

      day ->
        if remaining > 0 and checkpoint(context) == :ok do
          case refresh_day(feature, id, day, context) do
            :ok -> refresh_requested(feature, id, from, to, context, remaining - 1, used + 1)
            _ -> {used + 1, true}
          end
        else
          {used, true}
        end
    end
  end

  defp requested_day(feature, id, from, to) do
    case Repo.query!(
           """
           SELECT s.day FROM analytics_report_states s
           LEFT JOIN analytics_report_snapshots p ON p.id=s.snapshot_id
           WHERE s.feature=$1 AND s.branch_id=$2::text::uuid AND s.day BETWEEN $3 AND $4
             AND (s.snapshot_id IS NULL OR s.revision>p.revision)
           ORDER BY s.day DESC LIMIT 1
           """,
           [feature, id, from, to]
         ).rows do
      [[day]] -> day
      _ -> nil
    end
  end

  defp with_lock(feature, branch_id, fun) do
    Repo.checkout(fn ->
      key = "analytics-report:" <> feature <> ":" <> branch_id

      case Repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1,0))", [key]).rows do
        [[true]] ->
          try do
            fun.()
          after
            Repo.query!("SELECT pg_advisory_unlock(hashtextextended($1,0))", [key])
          end

        _ ->
          {:snooze, 2}
      end
    end)
  end

  defp checkpoint(%{deadline: deadline} = context) do
    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        {:snooze, 2}

      not Features.still_enabled?(context.feature, context.scope, context.generation) ->
        {:error, :disabled}

      true ->
        :ok
    end
  end

  defp checkpoint(context), do: Background.checkpoint(context)

  defp publish_result(%{deadline: _} = context, fun),
    do: Features.with_enabled(context.feature, context.scope, context.generation, fun)

  defp publish_result(context, fun), do: Background.publish(context, fun)

  defp ensure_collected_days(feature, id, from, to) when is_binary(id),
    do: ensure_collected_days(feature, [id], from, to)

  defp ensure_collected_days(_feature, [], _from, _to), do: :ok

  defp ensure_collected_days(feature, ids, from, to) do
    Repo.query!(
      """
      WITH branches AS (
        SELECT b.id,COALESCE(bi.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow') zone
        FROM unnest($2::uuid[]) b(id) LEFT JOIN branch_info bi ON bi.branch_id=b.id
      ), gates AS (
        SELECT scope_key,enabled,inserted_at,
          lead(inserted_at,1,'infinity'::timestamp) OVER
            (PARTITION BY scope_key ORDER BY inserted_at,id) until_at
        FROM feature_audits WHERE feature=$1 AND
          (scope_key='franchise' OR scope_key=ANY(SELECT 'branch:'||id::text FROM branches))
      ), days AS (
        SELECT b.id,d::date AS day,
          (d::timestamp AT TIME ZONE b.zone AT TIME ZONE 'UTC') start_at,
          ((d::date+1)::timestamp AT TIME ZONE b.zone AT TIME ZONE 'UTC') end_at
        FROM branches b CROSS JOIN LATERAL generate_series(
          GREATEST($3::date,CASE WHEN $1='analytics_extended' THEN
            (CURRENT_DATE-interval '36 months')::date ELSE
            (now() AT TIME ZONE b.zone)::date-89 END),
          LEAST($4::date,(now() AT TIME ZONE b.zone)::date),interval '1 day') d
      )
      INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at)
      SELECT $1,d.id,d.day,0,timezone('UTC',now()),timezone('UTC',now()) FROM days d
      WHERE EXISTS (
        SELECT 1 FROM gates p JOIN gates b ON b.scope_key='branch:'||d.id::text
        WHERE p.scope_key='franchise' AND p.enabled AND b.enabled
          AND GREATEST(p.inserted_at,b.inserted_at,d.start_at)<LEAST(p.until_at,b.until_at,d.end_at)
      )
      ON CONFLICT (feature,branch_id,day) DO NOTHING
      """,
      [feature, Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
    )
  end

  defp finalize_closed_days(feature, id, today) do
    # A bucket published while its day was open gets one final closed-day pass.
    # Existing historical dirty revisions remain the source of late corrections.
    Repo.query!(
      """
      UPDATE analytics_report_states s SET revision=s.revision+1,updated_at=timezone('UTC',now())
      FROM analytics_report_snapshots p
      WHERE s.snapshot_id=p.id AND s.feature=$1 AND s.branch_id=$2::text::uuid
        AND s.day<$3 AND s.revision=p.revision
        AND p.source_asof<((s.day+1)::timestamp AT TIME ZONE $4 AT TIME ZONE 'UTC')
        AND (s.day >= (CURRENT_DATE-interval '36 months')::date OR $1<>'analytics_extended')
      """,
      [
        feature,
        id,
        today,
        LocalTime.timezone(id)
      ]
    )
  end

  defp kind("analytics_funnel"), do: "analytics.funnel"
  defp kind("analytics_links"), do: "analytics.links"
  defp kind("analytics_extended"), do: "analytics.extended"

  defp refresh_pending(feature, branch_id, today, context) do
    refresh_pending(feature, branch_id, today, context, @days_per_run, [])
  end

  defp refresh_pending(_feature, _branch_id, _today, _context, 0, _processed), do: :ok

  defp refresh_pending(feature, branch_id, today, context, remaining, processed) do
    case pending_day(feature, branch_id, today, processed) do
      nil ->
        :ok

      {day, _revision} ->
        case refresh_day(feature, branch_id, day, context) do
          :ok ->
            refresh_pending(feature, branch_id, today, context, remaining - 1, [day | processed])

          other ->
            other
        end
    end
  end

  defp pending_day(feature, branch_id, today, processed) do
    oldest =
      if feature == "analytics_extended",
        do: Date.shift(Date.utc_today(), month: -36),
        else: Date.add(today, -89)

    Repo.query!(
      """
      SELECT s.day, s.revision FROM analytics_report_states s
      LEFT JOIN analytics_report_snapshots p ON p.id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=$2::text::uuid
        AND (s.day >= $4 OR (s.snapshot_id IS NOT NULL AND $1 <> 'analytics_extended'))
        AND (s.snapshot_id IS NULL OR s.revision>p.revision)
        AND NOT (s.day=ANY($5::date[]))
      ORDER BY CASE WHEN s.day=$3 THEN 0 ELSE 1 END, s.day LIMIT 1
      """,
      [feature, branch_id, today, oldest, processed]
    ).rows
    |> case do
      [[day, revision]] -> {day, revision}
      _ -> nil
    end
  end

  defp refresh_day(feature, branch_id, day, context) do
    snapshot = Ecto.UUID.generate()

    result =
      with :ok <- checkpoint(context),
           {:ok, {revision, source_asof}} <-
             stage(snapshot, feature, branch_id, day, context),
           :ok <- staged(feature, branch_id, day, revision),
           :ok <- checkpoint(context),
           {:ok, :ok} <-
             publish(snapshot, feature, branch_id, day, revision, source_asof, context) do
        :ok
      else
        {:error, _} = error -> error
        {:snooze, _} = snooze -> snooze
        other -> {:error, {:publication_failed, other}}
      end

    discard_unpublished(snapshot)
    result
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :query_canceled do
        {:snooze, 2}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp staged(feature, branch_id, day, revision) do
    :telemetry.execute(
      [:delivest, :analytics, :reports, :staged],
      %{},
      %{feature: feature, branch_id: branch_id, day: day, revision: revision}
    )

    :ok
  end

  defp stage(snapshot, feature, branch_id, day, context) do
    Repo.transaction(fn ->
      # SHOW does not establish a data snapshot. SET runs before the first data
      # query on an owned transaction; a sandbox owner may already be at RR.
      [[level]] = Repo.query!("SHOW transaction_isolation").rows

      if level != "repeatable read",
        do: Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

      [["repeatable read"]] = Repo.query!("SHOW transaction_isolation").rows

      previous_timeout =
        if Map.has_key?(context, :deadline) do
          [[previous]] = Repo.query!("SHOW statement_timeout").rows
          remaining = min(max(context.deadline - System.monotonic_time(:millisecond), 1), 250)

          Repo.query!("SELECT set_config('statement_timeout',$1,true)", [
            Integer.to_string(remaining)
          ])

          previous
        end

      [[revision, source_asof]] =
        Repo.query!(
          "SELECT revision, timezone('UTC', statement_timestamp()) FROM analytics_report_states WHERE feature=$1 AND branch_id=$2::text::uuid AND day=$3",
          [feature, branch_id, day]
        ).rows

      Repo.query!(
        """
        INSERT INTO analytics_report_snapshots
        (id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at)
        VALUES ($1::text::uuid,$2,$3::text::uuid,$4,$5,$6,$7,$8,$8)
        """,
        [
          snapshot,
          feature,
          branch_id,
          day,
          revision,
          context.generation.franchise,
          context.generation.branch,
          source_asof
        ]
      )

      with :ok <- write_rows(snapshot, calculated_rows(feature, branch_id, day)),
           :ok <- write_customers(feature, snapshot, branch_id, day, @zero, context),
           :ok <- write_links(feature, snapshot, branch_id, day, @zero, context) do
        if previous_timeout,
          do: Repo.query!("SELECT set_config('statement_timeout',$1,true)", [previous_timeout])

        {revision, source_asof}
      else
        other -> Repo.rollback(other)
      end
    end)
    |> case do
      {:error, {:error, _} = error} -> error
      {:error, {:snooze, _} = snooze} -> snooze
      other -> other
    end
  end

  defp calculated_rows("analytics_funnel" = feature, branch_id, day) do
    rows = Calculator.calculate(feature, branch_id, day)
    today = LocalTime.today(LocalTime.timezone(branch_id))

    if Date.diff(today, day) >= 90 do
      retained =
        published_rows(feature, branch_id, day, "stage") ++
          published_rows(feature, branch_id, day, "session_source")

      Enum.reject(rows, &(&1.dimension in ["stage", "session_source"])) ++ retained
    else
      rows
    end
  end

  defp calculated_rows(feature, branch_id, day), do: Calculator.calculate(feature, branch_id, day)

  defp published_rows(feature, branch_id, day, dimension) do
    Repo.query!(
      """
      SELECT r.family,r.dimension,r.key,r.counts FROM analytics_report_states s
      JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=$2::text::uuid AND s.day=$3
        AND r.dimension=$4
      """,
      [feature, branch_id, day, dimension]
    ).rows
    |> Enum.map(fn [family, dimension, key, counts] ->
      %{family: family, dimension: dimension, key: key, counts: counts}
    end)
  end

  defp write_customers("analytics_extended", snapshot, branch_id, day, after_id, context) do
    with :ok <- checkpoint(context) do
      {rows, full?} = Calculator.customer_batch(branch_id, day, after_id, @customer_batch)

      with :ok <- write_rows(snapshot, rows) do
        if full? do
          write_customers(
            "analytics_extended",
            snapshot,
            branch_id,
            day,
            List.last(rows).key,
            context
          )
        else
          :ok
        end
      end
    end
  end

  defp write_customers(_, _, _, _, _, _), do: :ok

  defp write_links("analytics_links", snapshot, branch_id, day, after_id, context) do
    with :ok <- checkpoint(context) do
      today = LocalTime.today(LocalTime.timezone(branch_id))
      preserve_clicks? = Date.diff(today, day) >= 90
      rows = Calculator.link_batch(branch_id, day, after_id, @link_batch, preserve_clicks?)

      with :ok <- write_rows(snapshot, rows) do
        if length(rows) < @link_batch do
          :ok
        else
          write_links("analytics_links", snapshot, branch_id, day, List.last(rows).key, context)
        end
      end
    end
  end

  defp write_links(_, _, _, _, _, _), do: :ok

  defp write_rows(_snapshot, []), do: :ok

  defp write_rows(snapshot, rows) do
    Repo.query!(
      """
      INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts)
      SELECT $1::text::uuid, x.family, x.dimension, x.key, x.counts::jsonb
      FROM unnest($2::text[],$3::text[],$4::text[],$5::text[])
        AS x(family,dimension,key,counts)
      """,
      [
        snapshot,
        Enum.map(rows, & &1.family),
        Enum.map(rows, & &1.dimension),
        Enum.map(rows, & &1.key),
        Enum.map(rows, &Jason.encode!(&1.counts))
      ]
    )

    :ok
  end

  defp publish(snapshot, feature, branch_id, day, revision, now, context) do
    publish_result(context, fn ->
      {count, _} =
        Repo.query!(
          """
          UPDATE analytics_report_states
          SET snapshot_id=$1::text::uuid, published_at=timezone('UTC',now()),
              source_asof=$2, updated_at=timezone('UTC',now())
          WHERE feature=$3 AND branch_id=$4::text::uuid AND day=$5 AND revision >= $6
            AND (snapshot_id IS NULL OR $6 >
              (SELECT revision FROM analytics_report_snapshots WHERE id=snapshot_id))
          """,
          [snapshot, now, feature, branch_id, day, revision]
        )
        |> then(&{&1.num_rows, &1.rows})

      # A newer calculation may already have won. The old staged snapshot is
      # discarded by the caller; it must not turn the completed job into an error.
      if count in [0, 1], do: :ok
    end)
  end

  defp discard_unpublished(snapshot) do
    Repo.query!(
      """
      DELETE FROM analytics_report_snapshots
      WHERE id=$1::text::uuid AND NOT EXISTS
        (SELECT 1 FROM analytics_report_states WHERE snapshot_id=$1::text::uuid)
      """,
      [snapshot]
    )
  end
end
