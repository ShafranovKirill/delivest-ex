defmodule Delivest.Analytics.Reports.Query do
  @moduledoc "SQL-only reads of published buckets; a request never loads all dimension rows."
  alias Delivest.Repo

  @page_size 50
  @metrics ~w(sessions created converted_sessions completed_sessions paid_online_sessions
    unlinked_orders_created_day awaiting_payment cash_method completed cancelled
    authorized_receipts clicks first_source_clients revenue refunded authorized_orders
    unknown_identity_orders)
  @sums Enum.map_join(@metrics, ",\n", fn metric ->
          "COALESCE(sum((r.counts->>'#{metric}')::bigint),0)::bigint AS #{metric}"
        end)

  def page_size, do: @page_size

  def schedule_health([], _kind), do: {:ok, %{state: :queued, last_success_at: nil}}

  def schedule_health(ids, kind) do
    ids = Enum.map(ids, &Ecto.UUID.dump!/1)

    [[checked, errors, missing, overdue]] =
      Repo.query!(
        """
        SELECT min(s.last_success_at),
          COALESCE(bool_or(s.last_error_at IS NOT NULL AND
            (s.last_success_at IS NULL OR s.last_error_at>s.last_success_at)),false),
          count(*) FILTER (WHERE s.id IS NULL OR s.last_success_at IS NULL)::bigint,
          COALESCE(bool_or(s.next_at < timezone('UTC',now()) AND NOT s.running),false)
        FROM unnest($1::uuid[]) b(id)
        LEFT JOIN background_schedules s ON s.scope_key='branch:' || b.id::text AND s.kind=$2
        """,
        [ids, kind]
      ).rows

    state =
      cond do
        errors -> :error
        missing > 0 or overdue -> :queued
        true -> :ready
      end

    {:ok, %{state: state, last_success_at: utc(checked)}}
  end

  def read(_feature, [], _from, _to, _tab, _filters, _page), do: empty()

  def read(feature, ids, from, to, tab, filters, page) do
    ids = Enum.map(ids, &Ecto.UUID.dump!/1)
    dimension = dimension(tab)
    key = key_filter(tab, filters)
    args = [feature, ids, from, to, dimension, key]

    customer_stats = customer_stats(feature, ids, from, to, tab, filters)

    %{
      rows: page_rows(args, page),
      total_rows: count_groups(args),
      totals: totals(args),
      coverage: coverage(feature, ids, from, to),
      branch_rows: branch_rows(feature, ids, from, to, tab, filters, page),
      branch_total: branch_total(feature, ids, from, to, tab, filters),
      verified_buyers: customer_stats.verified_buyers,
      repeat_buyers: customer_stats.repeat_buyers,
      retention: customer_stats.retention
    }
  end

  defp empty do
    %{
      rows: [],
      total_rows: 0,
      totals: %{},
      coverage: %{days: 0, complete_days: 0, partial_days: 0, asof: nil, dirty: false},
      branch_rows: [],
      branch_total: 0,
      verified_buyers: nil,
      repeat_buyers: nil,
      retention: nil
    }
  end

  defp dimension("funnel"), do: nil
  defp dimension("sources"), do: "link"
  defp dimension(_), do: "channel"

  defp key_filter("sources", %{"link_id" => key}) when is_binary(key) and key != "", do: key

  defp key_filter(tab, %{"channel" => key}) when tab != "funnel" and is_binary(key) and key != "",
    do: key

  defp key_filter(_, _), do: nil

  defp page_rows(args, page) do
    Repo.query!(
      """
      SELECT r.family,r.dimension,r.key,#{@sums}
      FROM analytics_report_states s
      JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
        AND ($5::text IS NULL OR r.dimension=$5)
        AND ($6::text IS NULL OR r.key=$6)
      GROUP BY r.family,r.dimension,r.key
      ORDER BY r.dimension,r.key LIMIT #{@page_size} OFFSET $7
      """,
      args ++ [(page - 1) * @page_size]
    ).rows
    |> Enum.map(fn [family, dimension, key | counts] ->
      %{
        family: family,
        dimension: dimension,
        key: key,
        counts: Map.new(Enum.zip(@metrics, counts))
      }
    end)
  end

  defp count_groups(args) do
    [[count]] =
      Repo.query!(
        """
        SELECT count(*)::bigint FROM (
          SELECT 1 FROM analytics_report_states s
          JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
          WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
            AND ($5::text IS NULL OR r.dimension=$5)
            AND ($6::text IS NULL OR r.key=$6)
          GROUP BY r.family,r.dimension,r.key
        ) grouped
        """,
        args
      ).rows

    count
  end

  defp totals(args) do
    [[created, completed, cancelled, revenue, refunded, sessions, clicks, first_sources]] =
      Repo.query!(
        """
        SELECT COALESCE(sum((r.counts->>'created')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'completed')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'cancelled')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'revenue')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'refunded')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'sessions')::bigint) FILTER
            (WHERE r.dimension='stage' AND r.key='session_started'),0)::bigint,
          COALESCE(sum((r.counts->>'clicks')::bigint),0)::bigint,
          COALESCE(sum((r.counts->>'first_source_clients')::bigint),0)::bigint
        FROM analytics_report_states s
        JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
        WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
          AND ($5::text IS NULL OR r.dimension=$5)
          AND ($6::text IS NULL OR r.key=$6)
        """,
        args
      ).rows

    %{
      "created" => created,
      "completed" => completed,
      "cancelled" => cancelled,
      "revenue" => revenue,
      "refunded" => refunded,
      "sessions" => sessions,
      "clicks" => clicks,
      "first_source_clients" => first_sources
    }
  end

  defp coverage(feature, ids, from, to) do
    [[days, partial_days, asof, dirty]] =
      Repo.query!(
        """
        WITH buckets AS (
          SELECT s.revision,s.source_asof,p.revision published_revision,s.branch_id,s.day,
            ((s.day::timestamp AT TIME ZONE
              COALESCE(bi.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow'))
              AT TIME ZONE 'UTC') start_at,
            (((s.day+1)::timestamp AT TIME ZONE
              COALESCE(bi.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow'))
              AT TIME ZONE 'UTC') end_at
          FROM analytics_report_states s
          JOIN analytics_report_snapshots p ON p.id=s.snapshot_id
          LEFT JOIN branch_info bi ON bi.branch_id=s.branch_id
          WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
        )
        SELECT count(*)::bigint,
          count(*) FILTER (WHERE
            parent.enabled IS DISTINCT FROM true OR branch.enabled IS DISTINCT FROM true OR
            EXISTS (SELECT 1 FROM feature_audits a WHERE a.feature=$1
              AND a.scope_key IN ('franchise','branch:'||b.branch_id::text)
              AND a.inserted_at > b.start_at AND a.inserted_at < b.end_at)
          )::bigint,
          min(b.source_asof),COALESCE(bool_or(b.revision>b.published_revision),false)
        FROM buckets b
        LEFT JOIN LATERAL (
          SELECT a.enabled FROM feature_audits a
          WHERE a.feature=$1 AND a.scope_key='franchise' AND a.inserted_at < b.end_at
          ORDER BY a.inserted_at DESC,a.id DESC LIMIT 1
        ) parent ON true
        LEFT JOIN LATERAL (
          SELECT a.enabled FROM feature_audits a
          WHERE a.feature=$1 AND a.scope_key='branch:'||b.branch_id::text
            AND a.inserted_at < b.end_at
          ORDER BY a.inserted_at DESC,a.id DESC LIMIT 1
        ) branch ON true
        """,
        [feature, ids, from, to]
      ).rows

    %{
      days: days,
      complete_days: days - partial_days,
      partial_days: partial_days,
      asof: utc(asof),
      dirty: dirty
    }
  end

  defp branch_rows(_feature, _ids, _from, _to, tab, _filters, _page) when tab != "franchise",
    do: []

  defp branch_rows(feature, ids, from, to, _tab, filters, page) do
    channel = key_filter("franchise", filters)

    Repo.query!(
      """
      SELECT s.branch_id::text,
        COALESCE(sum((r.counts->>'created')::bigint),0)::bigint,
        COALESCE(sum((r.counts->>'completed')::bigint),0)::bigint,
        COALESCE(sum((r.counts->>'cancelled')::bigint),0)::bigint,
        COALESCE(sum((r.counts->>'revenue')::bigint),0)::bigint
      FROM analytics_report_states s
      JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
      WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
        AND r.dimension='channel'
        AND ($5::text IS NULL OR r.key=$5)
      GROUP BY s.branch_id ORDER BY s.branch_id LIMIT #{@page_size} OFFSET $6
      """,
      [feature, ids, from, to, channel, (page - 1) * @page_size]
    ).rows
    |> Enum.map(fn [id, created, completed, cancelled, revenue] ->
      %{
        branch_id: id,
        counts: %{
          "created" => created,
          "completed" => completed,
          "cancelled" => cancelled,
          "revenue" => revenue
        }
      }
    end)
  end

  defp branch_total(_feature, _ids, _from, _to, tab, _filters) when tab != "franchise", do: 0

  defp branch_total(feature, ids, from, to, _tab, filters) do
    channel = key_filter("franchise", filters)

    [[count]] =
      Repo.query!(
        """
        SELECT count(DISTINCT s.branch_id)::bigint FROM analytics_report_states s
        JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
        WHERE s.feature=$1 AND s.branch_id=ANY($2::uuid[]) AND s.day BETWEEN $3 AND $4
          AND r.dimension='channel' AND ($5::text IS NULL OR r.key=$5)
        """,
        [feature, ids, from, to, channel]
      ).rows

    count
  end

  defp customer_stats(feature, _ids, _from, _to, tab, _filters)
       when feature != "analytics_extended" or tab not in ["customers", "franchise"],
       do: %{verified_buyers: nil, repeat_buyers: nil, retention: nil}

  defp customer_stats(_feature, ids, from, to, _tab, filters) do
    channel = Map.get(filters, "channel")
    dimension = if is_binary(channel) and channel != "", do: "customer:" <> channel, else: nil
    days = Date.diff(to, from) + 1
    previous_from = Date.add(from, -days)
    previous_to = Date.add(from, -1)

    [[unique, repeat, returning, prior]] =
      Repo.query!(
        """
        WITH buyers AS (
          SELECT r.key,
            sum((r.counts->>'orders')::bigint) FILTER (WHERE s.day BETWEEN $2 AND $3) current_orders,
            sum((r.counts->>'orders')::bigint) FILTER (WHERE s.day BETWEEN $4 AND $5) prior_orders
          FROM analytics_report_states s JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
          WHERE s.feature='analytics_extended' AND s.branch_id=ANY($1::uuid[])
            AND s.day BETWEEN $4 AND $3 AND r.dimension LIKE 'customer:%'
            AND ($6::text IS NULL OR r.dimension=$6)
          GROUP BY r.key
        )
        SELECT count(*) FILTER (WHERE current_orders>0)::bigint,
          count(*) FILTER (WHERE current_orders>1)::bigint,
          count(*) FILTER (WHERE current_orders>0 AND prior_orders>0)::bigint,
          count(*) FILTER (WHERE prior_orders>0)::bigint
        FROM buyers
        """,
        [ids, from, to, previous_from, previous_to, dimension]
      ).rows

    current_coverage = coverage("analytics_extended", ids, from, to).complete_days
    prior_coverage = coverage("analytics_extended", ids, previous_from, previous_to).complete_days
    expected = length(ids) * days

    retention =
      if current_coverage == expected and prior_coverage == expected and prior > 0,
        do: Float.round(100 * returning / prior, 1),
        else: nil

    %{verified_buyers: unique, repeat_buyers: repeat, retention: retention}
  end

  defp utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc(value), do: value
end
