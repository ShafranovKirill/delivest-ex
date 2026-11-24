defmodule Delivest.Analytics.Reports.OrderedFunnel do
  @moduledoc """
  Ordered, session-cohort storefront reach. A cart_add can be the first
  observable menu exposure (quick add); product_view can be a direct entry.
  Every stage selects the first qualifying event after the preceding stage,
  ordering ties by the immutable event id.
  """

  alias Delivest.Repo

  @version 2
  def version, do: @version

  def calculate(branch_id, start_at, end_at) do
    [
      [
        started,
        menu,
        cart,
        checkout,
        ordered,
        direct_product,
        quick_add,
        direct_checkout,
        out_of_order_checkout,
        linked_without_checkout,
        linked_before_checkout
      ]
    ] =
      Repo.query!(
        """
        WITH cohort AS (
          SELECT s.id FROM funnel_sessions s
          WHERE s.branch_id=$1::text::uuid AND s.started_at >= $2 AND s.started_at < $3
        ), reached AS (
          SELECT s.id, m.event menu_event, c.id cart_id, ch.received_at checkout_at,
            EXISTS (
              SELECT 1 FROM funnel_order_receipts r JOIN orders o ON o.id=r.order_id
              WHERE r.session_id=s.id AND o.branch_id=$1::text::uuid
                AND o.deleted_at IS NULL AND r.as_of_at >= ch.received_at
            ) ordered,
            EXISTS (
              SELECT 1 FROM funnel_events e
              WHERE e.session_id=s.id AND e.event='checkout_start'
            ) any_checkout,
            EXISTS (
              SELECT 1 FROM funnel_order_receipts r JOIN orders o ON o.id=r.order_id
              WHERE r.session_id=s.id AND o.branch_id=$1::text::uuid
                AND o.deleted_at IS NULL
            ) any_linked_order
          FROM cohort s
          LEFT JOIN LATERAL (
            SELECT e.id,e.received_at,e.event FROM funnel_events e
            WHERE e.session_id=s.id AND e.event IN ('menu_view','product_view','cart_add')
            ORDER BY e.received_at,e.id LIMIT 1
          ) m ON true
          LEFT JOIN LATERAL (
            SELECT e.id,e.received_at FROM funnel_events e
            WHERE e.session_id=s.id AND e.event='cart_add'
              AND (e.received_at,e.id) >= (m.received_at,m.id)
            ORDER BY e.received_at,e.id LIMIT 1
          ) c ON true
          LEFT JOIN LATERAL (
            SELECT e.id,e.received_at FROM funnel_events e
            WHERE e.session_id=s.id AND e.event='checkout_start'
              AND (e.received_at,e.id) > (c.received_at,c.id)
            ORDER BY e.received_at,e.id LIMIT 1
          ) ch ON true
        )
        SELECT count(*)::bigint,
          count(*) FILTER (WHERE menu_event IS NOT NULL)::bigint,
          count(*) FILTER (WHERE cart_id IS NOT NULL)::bigint,
          count(*) FILTER (WHERE checkout_at IS NOT NULL)::bigint,
          count(*) FILTER (WHERE checkout_at IS NOT NULL AND ordered)::bigint,
          count(*) FILTER (WHERE menu_event='product_view')::bigint,
          count(*) FILTER (WHERE menu_event='cart_add')::bigint,
          count(*) FILTER (WHERE any_checkout AND cart_id IS NULL)::bigint,
          count(*) FILTER (WHERE any_checkout AND cart_id IS NOT NULL AND checkout_at IS NULL)::bigint,
          count(*) FILTER (WHERE any_linked_order AND checkout_at IS NULL)::bigint,
          count(*) FILTER (WHERE any_linked_order AND checkout_at IS NOT NULL AND NOT ordered)::bigint
        FROM reached
        """,
        [branch_id, start_at, end_at]
      ).rows

    counts = [
      {"session_started", started},
      {"menu_view", menu},
      {"cart_add", cart},
      {"checkout_start", checkout},
      {"order_created", ordered}
    ]

    stages =
      counts
      |> Enum.with_index()
      |> Enum.map(fn {{key, sessions}, index} ->
        previous = if index == 0, do: nil, else: counts |> Enum.at(index - 1) |> elem(1)
        next = if index == 4, do: nil, else: counts |> Enum.at(index + 1) |> elem(1)

        %{
          family: "funnel",
          dimension: "stage",
          key: key,
          counts: %{
            "algorithm_version" => @version,
            "sessions" => sessions,
            "from_previous_percent" => percent(sessions, previous),
            "from_start_percent" => percent(sessions, started),
            "lost_to_next" => if(next == nil, do: nil, else: sessions - next)
          }
        }
      end)

    coverage = %{
      family: "funnel",
      dimension: "coverage",
      key: "paths",
      counts: %{
        "algorithm_version" => @version,
        "direct_product_entry" => direct_product,
        "quick_add_entry" => quick_add,
        "checkout_without_cart_event" => direct_checkout,
        "checkout_out_of_order" => out_of_order_checkout,
        "linked_order_without_checkout" => linked_without_checkout,
        "linked_order_before_checkout" => linked_before_checkout
      }
    }

    stages ++ [coverage]
  end

  defp percent(_, nil), do: nil
  defp percent(_, 0), do: nil
  defp percent(numerator, denominator), do: Float.round(numerator * 100 / denominator, 2)
end
