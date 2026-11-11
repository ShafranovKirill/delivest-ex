defmodule Delivest.Analytics.Reports.Calculator do
  @moduledoc "Bounded daily source queries. All monetary values remain integer kopecks."

  alias Delivest.{LocalTime, Repo}

  @funnel_events ~w(visit menu_view product_view cart_add checkout_start fulfillment_selected)

  def calculate("analytics_funnel", branch_id, day) do
    {start_at, end_at} = bounds(branch_id, day)

    event_rows =
      Repo.query!(
        """
        SELECT e.event, count(DISTINCT e.session_id)::bigint
        FROM funnel_events e JOIN funnel_sessions s ON s.id=e.session_id
        WHERE s.branch_id=$1::text::uuid AND s.started_at >= $2 AND s.started_at < $3
          AND e.event = ANY($4::text[])
        GROUP BY event
        """,
        [branch_id, start_at, end_at, @funnel_events]
      ).rows

    stages =
      for [event, count] <- event_rows,
          do: row("funnel", "stage", event, %{"sessions" => count})

    [[started]] =
      Repo.query!(
        "SELECT count(*)::bigint FROM funnel_sessions WHERE branch_id=$1::text::uuid AND started_at >= $2 AND started_at < $3",
        [branch_id, start_at, end_at]
      ).rows

    stages = [row("funnel", "stage", "session_started", %{"sessions" => started}) | stages]

    source_rows =
      Repo.query!(
        """
        SELECT COALESCE(first_event.source_type,'unavailable'),count(*)::bigint
        FROM funnel_sessions s
        LEFT JOIN LATERAL (
          SELECT e.source_type FROM funnel_events e
          WHERE e.session_id=s.id ORDER BY e.received_at,e.id LIMIT 1
        ) first_event ON true
        WHERE s.branch_id=$1::text::uuid AND s.started_at >= $2 AND s.started_at < $3
        GROUP BY COALESCE(first_event.source_type,'unavailable')
        """,
        [branch_id, start_at, end_at]
      ).rows

    sources =
      for [source, count] <- source_rows,
          do: row("funnel", "session_source", source, %{"sessions" => count})

    order_rows =
      Repo.query!(
        """
        SELECT count(*)::bigint,
          count(DISTINCT r.session_id) FILTER (WHERE r.session_id IS NOT NULL)::bigint,
          count(DISTINCT r.session_id) FILTER (WHERE o.status='completed')::bigint,
          count(DISTINCT r.session_id) FILTER (WHERE o.payment_method='online' AND EXISTS (
            SELECT 1 FROM order_payments p WHERE p.order_id=o.id AND p.status='paid'
          ))::bigint,
          count(*) FILTER (WHERE o.awaiting_payment)::bigint,
          count(*) FILTER (WHERE o.status='completed')::bigint,
          count(*) FILTER (WHERE o.status='cancelled')::bigint,
          count(*) FILTER (WHERE o.payment_method='cash')::bigint,
          count(*) FILTER (WHERE r.owner_kind='client')::bigint
        FROM funnel_order_receipts r JOIN orders o ON o.id=r.order_id
        WHERE o.branch_id=$1::text::uuid AND r.session_started_at >= $2 AND r.session_started_at < $3
          AND o.deleted_at IS NULL
        """,
        [branch_id, start_at, end_at]
      ).rows

    [
      [
        created,
        converted_sessions,
        completed_sessions,
        paid_sessions,
        awaiting,
        completed,
        cancelled,
        cash,
        authorized
      ]
    ] = order_rows

    [[unlinked]] =
      Repo.query!(
        """
        SELECT count(*)::bigint FROM orders o
        LEFT JOIN funnel_order_receipts r ON r.order_id=o.id
        WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3
          AND o.deleted_at IS NULL AND r.order_id IS NULL
        """,
        [branch_id, start_at, end_at]
      ).rows

    stages ++
      sources ++
      [
        row("funnel", "order", "all", %{
          "created" => created,
          "converted_sessions" => converted_sessions,
          "completed_sessions" => completed_sessions,
          "paid_online_sessions" => paid_sessions,
          "unlinked_orders_created_day" => unlinked,
          "awaiting_payment" => awaiting,
          "cash_method" => cash,
          "completed" => completed,
          "cancelled" => cancelled,
          "authorized_receipts" => authorized
        })
      ]
  end

  def calculate("analytics_extended", branch_id, day) do
    {start_at, end_at} = bounds(branch_id, day)

    channels =
      Repo.query!(
        """
        WITH daily AS (
          SELECT o.id,o.source,o.status,o.total_amount,r.verified_client_id,r.owner_kind
          FROM orders o JOIN analytics_order_identities r ON r.order_id=o.id
          WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3 AND o.deleted_at IS NULL
        ), refunds AS (
          SELECT f.order_id, sum(f.amount)::bigint amount FROM order_refunds f
          JOIN daily d ON d.id=f.order_id WHERE f.status='succeeded' GROUP BY f.order_id
        )
        SELECT COALESCE(d.source, 'unknown'), count(*)::bigint,
          count(*) FILTER (WHERE d.status='completed')::bigint,
          COALESCE(sum(GREATEST(d.total_amount-COALESCE(f.amount,0),0)) FILTER (WHERE d.status='completed'), 0)::bigint,
          count(*) FILTER (WHERE d.status='cancelled')::bigint,
          count(DISTINCT d.verified_client_id) FILTER (WHERE d.status='completed')::bigint,
          count(*) FILTER (WHERE d.owner_kind='client')::bigint,
          count(*) FILTER (WHERE d.owner_kind='unknown')::bigint,
          COALESCE(sum(f.amount) FILTER (WHERE d.status='completed'),0)::bigint
        FROM daily d LEFT JOIN refunds f ON f.order_id=d.id
        GROUP BY COALESCE(d.source, 'unknown')
        """,
        [branch_id, start_at, end_at]
      ).rows

    channel_rows =
      for [
            source,
            created,
            completed,
            revenue,
            cancelled,
            verified_buyers,
            authorized_orders,
            unknown_identity,
            refunded
          ] <- channels,
          do:
            row("extended", "channel", source, %{
              "created" => created,
              "completed" => completed,
              "revenue" => revenue,
              "cancelled" => cancelled,
              "verified_buyers" => verified_buyers,
              "authorized_orders" => authorized_orders,
              "unknown_identity_orders" => unknown_identity,
              "refunded" => refunded
            })

    channel_rows
  end

  def calculate("analytics_links", _branch_id, _day), do: []

  def link_batch(branch_id, day, after_id, limit, preserve_clicks?) do
    {start_at, end_at} = bounds(branch_id, day)

    Repo.query!(
      """
      WITH ids AS (
        SELECT link_id FROM advertising_clicks
        WHERE branch_id=$1::text::uuid AND clicked_at >= $2 AND clicked_at < $3
          AND link_id > $4::text::uuid
        UNION
        SELECT link_id FROM client_first_sources
        WHERE landing_branch_id=$1::text::uuid AND clicked_at >= $2 AND clicked_at < $3
          AND link_id > $4::text::uuid
        UNION
        SELECT r.link_id FROM advertising_order_receipts r JOIN orders o ON o.id=r.order_id
        WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3
          AND o.deleted_at IS NULL AND r.link_id > $4::text::uuid
        UNION
        SELECT r.key::uuid FROM analytics_report_states s
        JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
        WHERE $6::boolean AND s.feature='analytics_links' AND s.branch_id=$1::text::uuid
          AND s.day=$7 AND r.dimension='link' AND r.key::uuid > $4::text::uuid
        ORDER BY link_id LIMIT $5
      ), clicks AS (
        SELECT c.link_id,count(*)::bigint n FROM advertising_clicks c JOIN ids i ON i.link_id=c.link_id
        WHERE c.branch_id=$1::text::uuid AND c.clicked_at >= $2 AND c.clicked_at < $3
        GROUP BY c.link_id
      ), first_sources AS (
        SELECT f.link_id,count(*)::bigint n FROM client_first_sources f JOIN ids i ON i.link_id=f.link_id
        WHERE f.landing_branch_id=$1::text::uuid AND f.clicked_at >= $2 AND f.clicked_at < $3
        GROUP BY f.link_id
      ), daily AS (
        SELECT o.id,o.status,o.total_amount,r.link_id
        FROM advertising_order_receipts r JOIN ids i ON i.link_id=r.link_id
        JOIN orders o ON o.id=r.order_id
        WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3
          AND o.deleted_at IS NULL
      ), refunds AS (
        SELECT f.order_id,sum(f.amount)::bigint amount FROM order_refunds f
        JOIN daily d ON d.id=f.order_id WHERE f.status='succeeded' GROUP BY f.order_id
      ), orders AS (
        SELECT d.link_id,count(*)::bigint created,
          count(*) FILTER (WHERE d.status='completed')::bigint completed,
          COALESCE(sum(GREATEST(d.total_amount-COALESCE(f.amount,0),0)) FILTER
            (WHERE d.status='completed'),0)::bigint revenue,
          count(*) FILTER (WHERE d.status='cancelled')::bigint cancelled,
          COALESCE(sum(f.amount) FILTER (WHERE d.status='completed'),0)::bigint refunded
        FROM daily d LEFT JOIN refunds f ON f.order_id=d.id GROUP BY d.link_id
      ), previous AS (
        SELECT r.key::uuid link_id,(r.counts->>'clicks')::bigint clicks
        FROM analytics_report_states s JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
        JOIN ids i ON i.link_id=r.key::uuid
        WHERE $6::boolean AND s.feature='analytics_links' AND s.branch_id=$1::text::uuid
          AND s.day=$7 AND r.dimension='link'
      )
      SELECT i.link_id::text,
        CASE WHEN $6::boolean THEN COALESCE(p.clicks,0) ELSE COALESCE(c.n,0) END,
        COALESCE(f.n,0),COALESCE(o.created,0),COALESCE(o.completed,0),
        COALESCE(o.revenue,0),COALESCE(o.cancelled,0),COALESCE(o.refunded,0)
      FROM ids i LEFT JOIN clicks c ON c.link_id=i.link_id
      LEFT JOIN first_sources f ON f.link_id=i.link_id
      LEFT JOIN orders o ON o.link_id=i.link_id
      LEFT JOIN previous p ON p.link_id=i.link_id
      ORDER BY i.link_id
      """,
      [branch_id, start_at, end_at, after_id, limit, preserve_clicks?, day]
    ).rows
    |> Enum.map(fn [id, clicks, first_sources, created, completed, revenue, cancelled, refunded] ->
      row("links", "link", id, %{
        "clicks" => clicks,
        "first_source_clients" => first_sources,
        "created" => created,
        "completed" => completed,
        "revenue" => revenue,
        "cancelled" => cancelled,
        "refunded" => refunded
      })
    end)
  end

  def customer_batch(branch_id, day, after_id, limit) do
    {start_at, end_at} = bounds(branch_id, day)

    Repo.query!(
      """
      WITH clients AS (
        SELECT DISTINCT r.verified_client_id
        FROM orders o JOIN analytics_order_identities r ON r.order_id=o.id
        WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3
          AND o.deleted_at IS NULL AND o.status='completed' AND r.verified_client_id IS NOT NULL
          AND r.verified_client_id > $4::text::uuid
        ORDER BY r.verified_client_id LIMIT $5
      ), daily AS (
        SELECT o.id,o.total_amount,o.source,r.verified_client_id
        FROM orders o JOIN analytics_order_identities r ON r.order_id=o.id
        JOIN clients c ON c.verified_client_id=r.verified_client_id
        WHERE o.branch_id=$1::text::uuid AND o.inserted_at >= $2 AND o.inserted_at < $3
          AND o.deleted_at IS NULL AND o.status='completed' AND r.verified_client_id IS NOT NULL
      ), refunds AS (
        SELECT f.order_id,sum(f.amount)::bigint amount FROM order_refunds f
        JOIN daily d ON d.id=f.order_id WHERE f.status='succeeded' GROUP BY f.order_id
      )
      SELECT d.verified_client_id::text,COALESCE(d.source,'unknown'),count(*)::bigint,
        sum(GREATEST(d.total_amount-COALESCE(f.amount,0),0))::bigint
      FROM daily d LEFT JOIN refunds f ON f.order_id=d.id
      GROUP BY d.verified_client_id,COALESCE(d.source,'unknown')
      ORDER BY d.verified_client_id,COALESCE(d.source,'unknown')
      """,
      [branch_id, start_at, end_at, after_id, limit]
    ).rows
    |> then(fn rows ->
      full? = rows |> Enum.map(&hd/1) |> Enum.uniq() |> length() == limit

      rows =
        Enum.map(rows, fn [client_id, source, orders, revenue] ->
          row("extended", "customer:" <> source, client_id, %{
            "orders" => orders,
            "revenue" => revenue
          })
        end)

      {rows, full?}
    end)
  end

  defp bounds(branch_id, day) do
    zone = LocalTime.timezone(branch_id)
    {LocalTime.start_of_day_utc(day, zone), LocalTime.start_of_day_utc(Date.add(day, 1), zone)}
  end

  defp row(family, dimension, key, counts),
    do: %{family: family, dimension: dimension, key: key, counts: counts}
end
