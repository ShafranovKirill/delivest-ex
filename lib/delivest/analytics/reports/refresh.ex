defmodule Delivest.Analytics.Reports.Refresh do
  @moduledoc "Refresh one dirty branch/day bucket through the shared background runner."
  alias Delivest.{Background, LocalTime, Repo}
  alias Delivest.Analytics.Reports.Calculator

  @customer_batch 500
  @link_batch 500
  @days_per_run 2
  @zero "00000000-0000-0000-0000-000000000000"

  def perform({:branch, branch_id}, %{feature: feature} = context)
      when feature in ["analytics_funnel", "analytics_links", "analytics_extended"] do
    with :ok <- Background.checkpoint(context) do
      day = LocalTime.today(LocalTime.timezone(branch_id))
      ensure_today(feature, branch_id, day)
      result = refresh_pending(feature, branch_id, day, context)

      if result == :ok and pending_day(feature, branch_id, day, []) != nil do
        Background.run_now(kind(feature), {:branch, branch_id}, new_work: true)
      end

      result
    end
  end

  def perform(_, _), do: {:error, :invalid_scope}

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

  defp ensure_today(feature, branch_id, day) do
    Repo.query!(
      """
      INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at)
      VALUES ($1,$2::text::uuid,$3,0,timezone('UTC', now()),timezone('UTC', now()))
      ON CONFLICT (feature,branch_id,day) DO NOTHING
      """,
      [feature, branch_id, day]
    )
  end

  defp pending_day(feature, branch_id, today, processed) do
    Repo.query!(
      """
      SELECT s.day, s.revision FROM analytics_report_states s
      LEFT JOIN analytics_report_snapshots p ON p.id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=$2::text::uuid
        AND (s.day > $4 OR s.snapshot_id IS NOT NULL)
        AND (s.snapshot_id IS NULL OR s.revision>p.revision)
        AND NOT (s.day=ANY($5::date[]))
      ORDER BY CASE WHEN s.day=$3 THEN 0 ELSE 1 END, s.day LIMIT 1
      """,
      [feature, branch_id, today, Date.add(today, -90), processed]
    ).rows
    |> case do
      [[day, revision]] -> {day, revision}
      _ -> nil
    end
  end

  defp refresh_day(feature, branch_id, day, context) do
    snapshot = Ecto.UUID.generate()

    result =
      with :ok <- Background.checkpoint(context),
           {:ok, {revision, source_asof}} <-
             stage(snapshot, feature, branch_id, day, context),
           :ok <- staged(feature, branch_id, day, revision),
           :ok <- Background.checkpoint(context),
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
      retained = published_rows(feature, branch_id, day, "stage")

      Enum.reject(rows, &(&1.dimension == "stage")) ++ retained
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
    with :ok <- Background.checkpoint(context) do
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
    with :ok <- Background.checkpoint(context) do
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
    Background.publish(context, fn ->
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
