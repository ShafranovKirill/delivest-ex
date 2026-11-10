defmodule Delivest.Marketing.Report do
  @moduledoc "Bounded, cached observational reports for marketing policies."
  import Ecto.Query

  alias Delivest.{Background, Features, Repo}
  alias Delivest.Marketing.Policy

  @page 50
  @max_days 90
  @refresh_seconds 86_400

  def request(policy, filters \\ %{})

  def request(%Policy{} = policy, filters) when is_map(filters) do
    with {:ok, from_on, to_on, branch_key} <- normalize_filters(policy, filters),
         {:ok, generation} <- Features.snapshot("marketing_policies", :franchise) do
      result =
        Features.with_enabled("marketing_policies", :franchise, generation, fn ->
          now = DateTime.utc_now(:microsecond)
          params = [Ecto.UUID.dump!(policy.id), from_on, to_on, branch_key]

          {inserted, _} =
            Repo.insert_all(
              "marketing_report_requests",
              [
                %{
                  id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
                  policy_id: hd(params),
                  from_on: from_on,
                  to_on: to_on,
                  branch_key: branch_key,
                  status: "pending",
                  requested_at: now,
                  updated_at: now
                }
              ],
              on_conflict: :nothing,
              conflict_target: [:policy_id, :from_on, :to_on, :branch_key]
            )

          [[id, status, phase, as_of, data]] =
            Repo.query!(
              """
              SELECT id, status, phase, as_of, data FROM marketing_report_requests
              WHERE policy_id=$1 AND from_on=$2 AND to_on=$3 AND branch_key=$4 FOR UPDATE
              """,
              params
            ).rows

          refresh_started? = status == "ready" and phase != "cleaning" and stale?(as_of)

          if refresh_started?, do: begin_refresh(id, now)

          {inserted == 1 or refresh_started?,
           public_result(id, if(refresh_started?, do: "pending", else: status), as_of, data)}
        end)

      case result do
        {:ok, {inserted?, response}} ->
          if inserted? do
            Background.invalidate("marketing.report", :franchise)
            Background.kick()
          end

          {:ok, response}

        error ->
          error
      end
    end
  end

  def request(_, _), do: {:error, :invalid_report_filters}

  @doc "Compare at most ten ready policy snapshots; shared orders are deduplicated in background work."
  def compare(policies, filters \\ %{})

  def compare(policies, filters)
      when is_list(policies) and length(policies) in 1..10 and is_map(filters) do
    with true <- Enum.all?(policies, &match?(%Policy{}, &1)),
         true <- Enum.uniq_by(policies, & &1.id) == policies,
         {:ok, from_on, to_on, branch_key} <- normalize_filters(hd(policies), filters),
         results <- Enum.map(policies, &request(&1, filters)),
         true <- Enum.all?(results, &match?({:ok, _}, &1)) do
      reports = Enum.map(results, fn {:ok, report} -> report end)

      rows =
        Enum.zip_with(policies, reports, fn policy, report ->
          %{policy_id: policy.id, status: report.status, as_of: report.as_of, data: report.data}
        end)

      if Enum.any?(reports, &(&1.status == :pending)) do
        {:ok, %{status: :pending, rows: rows, as_of: nil, data: nil}}
      else
        member_ids = reports |> Enum.map(& &1.id) |> Enum.sort()
        as_of_map = Map.new(reports, &{&1.id, DateTime.to_iso8601(&1.as_of)})

        key =
          :crypto.hash(
            :sha256,
            :erlang.term_to_binary({member_ids, from_on, to_on, branch_key, as_of_map})
          )
          |> Base.encode16(case: :lower)

        case create_comparison(key, member_ids, as_of_map) do
          {:ok, comparison} -> {:ok, Map.put(comparison, :rows, rows)}
          {:error, :stale} -> {:ok, %{status: :pending, rows: rows, as_of: nil, data: nil}}
          error -> error
        end
      end
    else
      _ -> {:error, :invalid_report_filters}
    end
  end

  def compare(_, _), do: {:error, :invalid_report_filters}

  defp create_comparison(key, member_ids, as_of_map) do
    with {:ok, generation} <- Features.snapshot("marketing_policies", :franchise) do
      case Features.with_enabled("marketing_policies", :franchise, generation, fn ->
             unless comparison_members_current?(%{
                      member_ids: Enum.map(member_ids, &Ecto.UUID.dump!/1),
                      member_as_of: as_of_map
                    }),
                    do: Repo.rollback(:stale)

             now = DateTime.utc_now(:microsecond)

             {inserted, _} =
               Repo.insert_all(
                 "marketing_report_comparisons",
                 [
                   %{
                     id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
                     request_key: key,
                     member_request_ids: Enum.map(member_ids, &Ecto.UUID.dump!/1),
                     member_as_of: as_of_map,
                     status: "pending",
                     requested_at: now,
                     updated_at: now
                   }
                 ],
                 on_conflict: :nothing,
                 conflict_target: [:request_key]
               )

             [[id, status, as_of, data]] =
               Repo.query!(
                 """
                 SELECT id,status,as_of,data FROM marketing_report_comparisons WHERE request_key=$1
                 """,
                 [key]
               ).rows

             {inserted == 1, public_result(id, status, as_of, data)}
           end) do
        {:ok, {inserted?, result}} ->
          if inserted? do
            Background.invalidate("marketing.report", :franchise)
            Background.kick()
          end

          {:ok, result}

        error ->
          error
      end
    end
  end

  def perform(:franchise, context) do
    with :ok <- Background.checkpoint(context) do
      result =
        case next_request() do
          nil -> :ok
          {:refresh, id} -> refresh(id, context)
          {:cleanup, id} -> cleanup_refresh(id, context)
          {:pending, request} -> process_page(request, context)
          {:comparison, comparison} -> process_comparison(comparison, context)
        end

      case result do
        :ok -> if(next_request(), do: {:snooze, 1}, else: :ok)
        other -> other
      end
    end
  end

  def perform(_, _), do: {:error, :invalid_scope}

  defp next_request do
    case Repo.query!("""
         SELECT id, policy_id, from_on, to_on, branch_key, requested_at,
                phase, cursor_issued_at, cursor_issue_id, cursor_order_at, cursor_order_id
         FROM marketing_report_requests WHERE status='pending' AND phase IN ('issues','orders')
         ORDER BY requested_at, id LIMIT 1
         """).rows do
      [
        [
          id,
          policy_id,
          from_on,
          to_on,
          branch_key,
          requested_at,
          phase,
          cursor_at,
          cursor_id,
          order_at,
          order_id
        ]
      ] ->
        {:pending,
         %{
           id: id,
           policy_id: policy_id,
           from_on: from_on,
           to_on: to_on,
           branch_key: branch_key,
           requested_at: requested_at,
           phase: phase,
           cursor_at: cursor_at,
           cursor_id: cursor_id,
           order_at: order_at,
           order_id: order_id
         }}

      [] ->
        case Repo.query!("""
             SELECT id,member_request_ids,member_as_of,cursor_order_id,requested_at
             FROM marketing_report_comparisons WHERE status='pending'
             ORDER BY requested_at,id LIMIT 1
             """).rows do
          [[id, member_ids, member_as_of, cursor_id, requested_at]] ->
            {:comparison,
             %{
               id: id,
               member_ids: member_ids,
               member_as_of: decode_json(member_as_of),
               cursor_id: cursor_id,
               requested_at: requested_at
             }}

          [] ->
            case Repo.query!(
                   "SELECT id FROM marketing_report_requests WHERE status='pending' AND phase='cleaning' ORDER BY updated_at,id LIMIT 1"
                 ).rows do
              [[id]] ->
                {:cleanup, id}

              [] ->
                cutoff = DateTime.add(DateTime.utc_now(:microsecond), -@refresh_seconds, :second)

                case Repo.query!(
                       """
                       SELECT id FROM marketing_report_requests WHERE status='ready'
                         AND phase<>'cleaning' AND as_of < $1
                       ORDER BY as_of, id LIMIT 1
                       """,
                       [cutoff]
                     ).rows do
                  [[id]] -> {:refresh, id}
                  _ -> nil
                end
            end
        end
    end
  end

  defp refresh(id, context) do
    case Background.publish(context, fn ->
           case Repo.query!(
                  "SELECT status, as_of FROM marketing_report_requests WHERE id=$1 FOR UPDATE",
                  [id]
                ).rows do
             [["ready", as_of]] ->
               if stale?(as_of), do: begin_refresh(id, DateTime.utc_now(:microsecond))

             _ ->
               :ok
           end
         end) do
      {:ok, _} -> :ok
      {:error, :disabled} -> {:error, :disabled}
      error -> error
    end
  end

  defp stale?(as_of) when not is_nil(as_of) do
    DateTime.diff(DateTime.utc_now(:microsecond), DateTime.from_naive!(as_of, "Etc/UTC"), :second) >=
      @refresh_seconds
  end

  defp stale?(_), do: true

  defp begin_refresh(id, now) do
    Repo.query!(
      "UPDATE marketing_report_requests SET status='pending',phase='cleaning',updated_at=$2 WHERE id=$1 AND status='ready'",
      [id, now]
    )

    Repo.query!(
      "UPDATE marketing_report_comparisons SET status='stale',updated_at=$2 WHERE status IN ('pending','ready') AND $1=ANY(member_request_ids)",
      [id, now]
    )
  end

  defp cleanup_refresh(id, context) do
    case Background.publish(context, fn ->
           case Repo.query!(
                  "SELECT status,phase FROM marketing_report_requests WHERE id=$1 FOR UPDATE",
                  [id]
                ).rows do
             [["pending", "cleaning"]] ->
               Repo.query!(
                 "DELETE FROM marketing_report_links WHERE ctid IN (SELECT ctid FROM marketing_report_links WHERE request_id=$1 LIMIT $2)",
                 [id, @page]
               )

               Repo.query!(
                 "DELETE FROM marketing_report_daily WHERE ctid IN (SELECT ctid FROM marketing_report_daily WHERE request_id=$1 LIMIT $2)",
                 [id, @page]
               )

               [[remaining]] =
                 Repo.query!(
                   "SELECT EXISTS(SELECT 1 FROM marketing_report_links WHERE request_id=$1) OR EXISTS(SELECT 1 FROM marketing_report_daily WHERE request_id=$1)",
                   [id]
                 ).rows

               unless remaining do
                 Repo.query!(
                   """
                   UPDATE marketing_report_requests SET status='pending', phase='issues',
                     cursor_issued_at=NULL, cursor_issue_id=NULL, cursor_order_at=NULL,
                     cursor_order_id=NULL, requested_at=$2, as_of=NULL, data=NULL, updated_at=$2
                   WHERE id=$1 AND status='pending' AND phase='cleaning'
                   """,
                   [id, DateTime.utc_now(:microsecond)]
                 )
               end

             _ ->
               :ok
           end
         end) do
      {:ok, _} -> :ok
      {:error, :disabled} -> {:error, :disabled}
      error -> error
    end
  end

  defp process_page(request, context) do
    case request.phase do
      "issues" -> process_issue_page(request, context)
      "orders" -> process_order_page(request, context)
      _ -> {:error, :invalid_report_phase}
    end
  end

  defp process_issue_page(request, context) do
    page = issue_page(request)
    ids = Enum.take(page, @page) |> Enum.map(&hd/1)
    done = length(page) <= @page
    last = List.last(Enum.take(page, @page))

    case Background.publish(context, fn ->
           case Repo.query!(
                  """
                  SELECT id FROM marketing_report_requests WHERE id=$1
                  """,
                  [request.id]
                ).rows do
             [[_]] ->
               locked_request!(request)

               if ids != [] do
                 stage_issue_metrics(request.id, ids)
               end

               if done do
                 Repo.query!(
                   """
                   UPDATE marketing_report_requests SET phase='orders', cursor_issued_at=NULL,
                     cursor_issue_id=NULL, updated_at=now() WHERE id=$1
                   """,
                   [request.id]
                 )
               else
                 advance_cursor(request.id, last)
               end

             _ ->
               Repo.rollback(:stale)
           end
         end) do
      {:ok, _} -> :ok
      {:error, :stale} -> :ok
      {:error, :disabled} -> {:error, :disabled}
      error -> error
    end
  end

  defp process_order_page(request, context) do
    case issue_page(%{request | order_at: nil, order_id: nil}) |> List.first() do
      nil ->
        case Background.publish(context, fn ->
               locked_request!(request)
               publish_snapshot(request)
             end) do
          {:ok, _} -> :ok
          {:error, :stale} -> :ok
          error -> error
        end

      [issue_id, issued_at] ->
        issue =
          Repo.query!("SELECT client_id, attribution_until FROM marketing_issues WHERE id=$1", [
            issue_id
          ]).rows

        [[client_id, until_at]] = issue

        upper =
          if NaiveDateTime.compare(until_at, request.requested_at) == :gt,
            do: request.requested_at,
            else: until_at

        page =
          Repo.query!(
            """
            SELECT id, inserted_at FROM orders WHERE client_id=$1 AND inserted_at<=$2
              AND ($3::timestamp IS NULL OR (inserted_at,id)>($3::timestamp,$4::uuid))
            ORDER BY inserted_at,id LIMIT $5
            """,
            [client_id, upper, request.order_at, request.order_id, @page + 1]
          ).rows

        order_ids = page |> Enum.take(@page) |> Enum.map(&hd/1)
        done = length(page) <= @page
        last_order = List.last(Enum.take(page, @page))

        case Background.publish(context, fn ->
               locked_request!(request)

               if order_ids != [],
                 do: stage_order_links(request.id, issue_id, order_ids, request.requested_at)

               if done do
                 Repo.query!(
                   """
                   UPDATE marketing_report_requests SET cursor_issue_id=$2, cursor_issued_at=$3,
                     cursor_order_at=NULL, cursor_order_id=NULL, updated_at=now() WHERE id=$1
                   """,
                   [request.id, issue_id, issued_at]
                 )
               else
                 [order_id, order_at] = last_order

                 Repo.query!(
                   """
                   UPDATE marketing_report_requests SET cursor_order_id=$2, cursor_order_at=$3,
                     updated_at=now() WHERE id=$1
                   """,
                   [request.id, order_id, order_at]
                 )
               end
             end) do
          {:ok, _} -> :ok
          {:error, :stale} -> :ok
          error -> error
        end
    end
  end

  defp locked_request!(request) do
    case Repo.query!(
           """
           SELECT status, phase, requested_at, cursor_issued_at, cursor_issue_id,
             cursor_order_at, cursor_order_id FROM marketing_report_requests WHERE id=$1 FOR UPDATE
           """,
           [request.id]
         ).rows do
      [["pending", phase, requested_at, cursor_at, cursor_id, order_at, order_id]]
      when phase == request.phase and requested_at == request.requested_at and
             cursor_at == request.cursor_at and cursor_id == request.cursor_id and
             order_at == request.order_at and order_id == request.order_id ->
        :ok

      _ ->
        Repo.rollback(:stale)
    end
  end

  defp issue_page(request) do
    Repo.query!(
      """
      SELECT id, issued_at FROM marketing_issues
      WHERE policy_id=$1 AND issued_at >= $2::date AND issued_at < ($3::date + INTERVAL '1 day')
        AND issued_at <= $4
        AND ($5='all' OR branch_id=NULLIF($5,'all')::uuid)
        AND ($6::timestamp IS NULL OR (issued_at, id) > ($6::timestamp, $7::uuid))
      ORDER BY issued_at, id LIMIT $8
      """,
      [
        request.policy_id,
        request.from_on,
        request.to_on,
        request.requested_at,
        request.branch_key,
        request.cursor_at,
        request.cursor_id,
        @page + 1
      ]
    ).rows
  end

  defp advance_cursor(id, [issue_id, issued_at]) do
    Repo.query!(
      """
      UPDATE marketing_report_requests SET cursor_issue_id=$2, cursor_issued_at=$3,
        updated_at=now() WHERE id=$1
      """,
      [id, issue_id, issued_at]
    )
  end

  defp stage_issue_metrics(request_id, issue_ids) do
    Repo.query!(
      """
      WITH facts AS (
        SELECT i.issued_at::date AS day, i.branch_id,
          CASE WHEN i.reward_type='bonus' THEN COALESCE(i.reward_amount,0) ELSE 0 END AS bonus,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_intents ci
            ON ci.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND ci.channel='in_app' AND ci.status='sent') AS in_app,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_intents ci
            ON ci.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND ci.channel='push' AND ci.status='sent') AS push_sent,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_intents ci
            ON ci.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND ci.channel='push' AND ci.status='unknown') AS push_unknown,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_intents ci
            ON ci.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND ci.channel='push' AND ci.status='skipped') AS push_skipped,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_intents ci
            ON ci.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND ci.channel='sms' AND ci.status='skipped') AS sms_unavailable,
          EXISTS (SELECT 1 FROM customer_notifications n JOIN customer_notification_events e
            ON e.notification_id=n.id WHERE n.source_type='marketing_reward'
              AND n.source_id=i.id AND e.kind='click') AS clicked,
          (SELECT count(*) FROM promo_redemptions r JOIN orders o ON o.id=r.order_id
            WHERE i.reward_type='promo' AND r.promo_code_id=i.reward_id
              AND o.status='completed' AND o.deleted_at IS NULL) AS promo_count,
          (SELECT COALESCE(sum(r.discount),0) FROM promo_redemptions r JOIN orders o ON o.id=r.order_id
            WHERE i.reward_type='promo' AND r.promo_code_id=i.reward_id
              AND o.status='completed' AND o.deleted_at IS NULL) AS promo_discount
        FROM marketing_issues i WHERE i.id=ANY($2::uuid[])
      ), grouped AS (
        SELECT day, branch_id, count(*)::integer AS issued, sum(COALESCE(bonus,0))::bigint AS bonus,
          count(*) FILTER (WHERE in_app)::integer AS in_app,
          count(*) FILTER (WHERE push_sent)::integer AS push_sent,
          count(*) FILTER (WHERE push_unknown)::integer AS push_unknown,
          count(*) FILTER (WHERE push_skipped)::integer AS push_skipped,
          count(*) FILTER (WHERE sms_unavailable)::integer AS sms_unavailable,
          count(*) FILTER (WHERE clicked)::integer AS clicked,
          sum(promo_count)::integer AS promo_count, sum(promo_discount)::bigint AS promo_discount
        FROM facts GROUP BY day, branch_id
      )
      INSERT INTO marketing_report_daily (request_id,day,branch_id,issued,bonus_points_issued,
        in_app_available,push_provider_accepted,push_unknown,push_skipped,sms_unavailable,
        clicked_notices,promo_redemptions,recorded_promo_discount)
      SELECT $1,day,branch_id,issued,bonus,in_app,push_sent,push_unknown,push_skipped,
        sms_unavailable,clicked,promo_count,promo_discount FROM grouped
      ON CONFLICT (request_id,day,branch_id) DO UPDATE SET
        issued=marketing_report_daily.issued+EXCLUDED.issued,
        bonus_points_issued=marketing_report_daily.bonus_points_issued+EXCLUDED.bonus_points_issued,
        in_app_available=marketing_report_daily.in_app_available+EXCLUDED.in_app_available,
        push_provider_accepted=marketing_report_daily.push_provider_accepted+EXCLUDED.push_provider_accepted,
        push_unknown=marketing_report_daily.push_unknown+EXCLUDED.push_unknown,
        push_skipped=marketing_report_daily.push_skipped+EXCLUDED.push_skipped,
        sms_unavailable=marketing_report_daily.sms_unavailable+EXCLUDED.sms_unavailable,
        clicked_notices=marketing_report_daily.clicked_notices+EXCLUDED.clicked_notices,
        promo_redemptions=marketing_report_daily.promo_redemptions+EXCLUDED.promo_redemptions,
        recorded_promo_discount=marketing_report_daily.recorded_promo_discount+EXCLUDED.recorded_promo_discount
      """,
      [request_id, issue_ids]
    )
  end

  defp stage_order_links(request_id, issue_id, order_ids, as_of) do
    Repo.query!(
      """
      WITH candidates AS (
        SELECT DISTINCT ON (o.id) o.id AS order_id, o.client_id, o.branch_id,
          i.branch_id AS issue_branch_id,
          i.issued_at::date AS issue_day,
          GREATEST(0, o.total_amount - COALESCE((SELECT sum(r.amount) FROM order_refunds r
            WHERE r.order_id=o.id AND r.status='succeeded'),0))::bigint AS net_revenue
        FROM marketing_issues i JOIN marketing_policies p ON p.id=i.policy_id
        JOIN orders o ON o.client_id=i.client_id AND o.status='completed'
          AND o.deleted_at IS NULL AND o.id<>i.cycle_order_id
        JOIN order_transitions t ON t.order_id=o.id AND t.to='completed' AND t.reverted_at IS NULL
        WHERE i.id=$2 AND o.id=ANY($3::uuid[]) AND t.inserted_at>i.issued_at
          AND t.inserted_at<=i.attribution_until
          AND t.inserted_at<=$4
          AND (p.scope='franchise' OR EXISTS (SELECT 1 FROM marketing_policy_branches b
            WHERE b.policy_id=p.id AND b.branch_id=o.branch_id))
        ORDER BY o.id, i.issued_at, i.id
      ), inserted AS (
        INSERT INTO marketing_report_links
          (request_id,order_id,client_id,branch_id,issue_branch_id,issue_day,net_revenue)
        SELECT $1,order_id,client_id,branch_id,issue_branch_id,issue_day,net_revenue FROM candidates
        ON CONFLICT (request_id,order_id) DO NOTHING
        RETURNING issue_day,issue_branch_id,net_revenue
      ), grouped AS (
        SELECT issue_day AS day, issue_branch_id, count(*)::integer AS orders,
          sum(net_revenue)::bigint AS revenue FROM inserted GROUP BY issue_day,issue_branch_id
      )
      INSERT INTO marketing_report_daily (request_id,day,branch_id,linked_orders,linked_net_revenue)
      SELECT $1,day,issue_branch_id,orders,revenue FROM grouped
      ON CONFLICT (request_id,day,branch_id) DO UPDATE SET
        linked_orders=marketing_report_daily.linked_orders+EXCLUDED.linked_orders,
        linked_net_revenue=marketing_report_daily.linked_net_revenue+EXCLUDED.linked_net_revenue
      """,
      [request_id, issue_id, order_ids, as_of]
    )
  end

  defp publish_snapshot(request) do
    [
      [
        issued,
        bonus,
        in_app,
        push_sent,
        push_unknown,
        push_skipped,
        sms_unavailable,
        clicked,
        orders,
        revenue,
        promo_count,
        promo_discount
      ]
    ] =
      Repo.query!(
        """
        SELECT COALESCE(sum(issued),0)::bigint, COALESCE(sum(bonus_points_issued),0)::bigint,
          COALESCE(sum(in_app_available),0), COALESCE(sum(push_provider_accepted),0),
          COALESCE(sum(push_unknown),0), COALESCE(sum(push_skipped),0),
          COALESCE(sum(sms_unavailable),0), COALESCE(sum(clicked_notices),0),
          COALESCE(sum(linked_orders),0)::bigint, COALESCE(sum(linked_net_revenue),0)::bigint,
          COALESCE(sum(promo_redemptions),0)::bigint, COALESCE(sum(recorded_promo_discount),0)::bigint
        FROM marketing_report_daily WHERE request_id=$1
        """,
        [request.id]
      ).rows

    [[returned_clients]] =
      Repo.query!(
        """
        SELECT count(DISTINCT client_id) FROM marketing_report_links WHERE request_id=$1
        """,
        [request.id]
      ).rows

    [[excluded]] =
      Repo.query!(
        """
        SELECT count(*) FROM marketing_exclusions e
        JOIN marketing_policies p ON p.id=e.policy_id
        WHERE e.policy_id=$1 AND e.inserted_at >= $2::date
          AND e.inserted_at < ($3::date + INTERVAL '1 day')
          AND ($4='all' OR p.reward_branch_id=NULLIF($4,'all')::uuid)
        """,
        [request.policy_id, request.from_on, request.to_on, request.branch_key]
      ).rows

    series =
      Repo.query!(
        """
        SELECT day, sum(issued)::bigint, sum(linked_orders)::bigint, sum(linked_net_revenue)::bigint
        FROM marketing_report_daily WHERE request_id=$1 GROUP BY day ORDER BY day
        """,
        [request.id]
      ).rows
      |> Enum.map(fn [day, day_issued, day_orders, day_revenue] ->
        %{
          day: Date.to_iso8601(day),
          issued: day_issued,
          linked_orders: day_orders,
          linked_net_revenue: day_revenue
        }
      end)

    data = %{
      issued: issued,
      excluded: excluded,
      in_app_available: in_app,
      push_provider_accepted: push_sent,
      push_unknown: push_unknown,
      push_skipped: push_skipped,
      sms_unavailable: sms_unavailable,
      clicked_notices: clicked,
      linked_orders: orders,
      linked_net_revenue: revenue,
      returned_clients: returned_clients,
      bonus_points_issued: bonus,
      bonus_points_used: nil,
      bonus_cost: nil,
      promo_redemptions: promo_count,
      recorded_promo_discount: promo_discount,
      sms_cost: nil,
      delivered: nil,
      attribution: "observational_post_issue",
      attribution_window: "Each issue's stored issued_at through attribution_until",
      series: series
    }

    Repo.query!(
      """
      UPDATE marketing_report_requests SET status='ready', as_of=requested_at,
        data=$2::jsonb, updated_at=now() WHERE id=$1 AND status='pending'
      """,
      [request.id, Jason.encode!(data)]
    )
  end

  defp process_comparison(comparison, context) do
    page =
      Repo.query!(
        """
        SELECT DISTINCT ON (l.order_id) l.order_id,l.client_id,l.branch_id,l.issue_day,l.net_revenue
        FROM marketing_report_links l
        WHERE l.request_id=ANY($1::uuid[])
          AND ($2::uuid IS NULL OR l.order_id>$2::uuid)
        ORDER BY l.order_id,l.issue_day,l.request_id LIMIT $3
        """,
        [comparison.member_ids, comparison.cursor_id, @page + 1]
      ).rows

    rows = Enum.take(page, @page)
    done = length(page) <= @page
    last = List.last(rows)

    case Background.publish(context, fn ->
           members_current? = comparison_members_current?(comparison)

           [[status, cursor_id, requested_at]] =
             Repo.query!(
               """
               SELECT status,cursor_order_id,requested_at FROM marketing_report_comparisons
               WHERE id=$1 FOR UPDATE
               """,
               [comparison.id]
             ).rows

           if status != "pending" or cursor_id != comparison.cursor_id or
                requested_at != comparison.requested_at,
              do: Repo.rollback(:stale)

           if members_current? do
             stage_comparison_rows(comparison.id, rows)

             if done do
               publish_comparison(comparison)
             else
               Repo.query!(
                 """
                 UPDATE marketing_report_comparisons SET cursor_order_id=$2,updated_at=now()
                 WHERE id=$1
                 """,
                 [comparison.id, hd(last)]
               )
             end
           else
             Repo.query!(
               "UPDATE marketing_report_comparisons SET status='stale',updated_at=now() WHERE id=$1",
               [comparison.id]
             )
           end
         end) do
      {:ok, _} -> :ok
      {:error, :stale} -> :ok
      {:error, :disabled} -> {:error, :disabled}
      error -> error
    end
  end

  defp comparison_members_current?(comparison) do
    rows =
      Repo.query!(
        """
        SELECT id,status,phase,as_of FROM marketing_report_requests
        WHERE id=ANY($1::uuid[]) ORDER BY id FOR SHARE
        """,
        [comparison.member_ids]
      ).rows

    length(rows) == length(comparison.member_ids) and
      Enum.all?(rows, fn [id, status, phase, as_of] ->
        status == "ready" and phase == "orders" and
          comparison.member_as_of[Ecto.UUID.load!(id)] ==
            DateTime.to_iso8601(DateTime.from_naive!(as_of, "Etc/UTC"))
      end)
  end

  defp stage_comparison_rows(_comparison_id, []), do: :ok

  defp stage_comparison_rows(comparison_id, rows) do
    clients =
      rows
      |> Enum.map(fn [_order_id, client_id | _] ->
        %{comparison_id: comparison_id, client_id: client_id}
      end)
      |> Enum.uniq()

    Repo.insert_all("marketing_report_comparison_clients", clients,
      on_conflict: :nothing,
      conflict_target: [:comparison_id, :client_id]
    )

    rows
    |> Enum.group_by(fn [_order_id, _client_id, branch_id, day, _net] -> {day, branch_id} end)
    |> Enum.each(fn {{day, branch_id}, group} ->
      revenue = Enum.reduce(group, 0, fn [_, _, _, _, net], sum -> sum + net end)

      Repo.query!(
        """
        INSERT INTO marketing_report_comparison_daily
          (comparison_id,day,branch_id,linked_orders,linked_net_revenue)
        VALUES ($1,$2,$3,$4,$5)
        ON CONFLICT (comparison_id,day,branch_id) DO UPDATE SET
          linked_orders=marketing_report_comparison_daily.linked_orders+EXCLUDED.linked_orders,
          linked_net_revenue=marketing_report_comparison_daily.linked_net_revenue+EXCLUDED.linked_net_revenue
        """,
        [comparison_id, day, branch_id, length(group), revenue]
      )
    end)
  end

  defp publish_comparison(comparison) do
    [[orders, revenue]] =
      Repo.query!(
        """
        SELECT COALESCE(sum(linked_orders),0)::bigint,
          COALESCE(sum(linked_net_revenue),0)::bigint
        FROM marketing_report_comparison_daily WHERE comparison_id=$1
        """,
        [comparison.id]
      ).rows

    [[clients]] =
      Repo.query!(
        """
        SELECT count(*) FROM marketing_report_comparison_clients WHERE comparison_id=$1
        """,
        [comparison.id]
      ).rows

    series =
      Repo.query!(
        """
        SELECT day,sum(linked_orders)::bigint,sum(linked_net_revenue)::bigint
        FROM marketing_report_comparison_daily WHERE comparison_id=$1
        GROUP BY day ORDER BY day
        """,
        [comparison.id]
      ).rows
      |> Enum.map(fn [day, count, net] ->
        %{day: Date.to_iso8601(day), linked_orders: count, linked_net_revenue: net}
      end)

    branch_rows =
      Repo.query!(
        """
        SELECT branch_id,sum(linked_orders)::bigint,sum(linked_net_revenue)::bigint
        FROM marketing_report_comparison_daily WHERE comparison_id=$1
        GROUP BY branch_id ORDER BY branch_id LIMIT 101
        """,
        [comparison.id]
      ).rows

    branches =
      branch_rows
      |> Enum.take(100)
      |> Enum.map(fn [id, count, net] ->
        %{branch_id: Ecto.UUID.load!(id), linked_orders: count, linked_net_revenue: net}
      end)

    data = %{
      linked_orders: orders,
      linked_net_revenue: revenue,
      returned_clients: clients,
      series: series,
      return_branches: branches,
      branches_truncated: length(branch_rows) > 100,
      attribution: "observational_post_issue",
      overlap: "orders counted once across policies",
      member_as_of: comparison.member_as_of
    }

    Repo.query!(
      """
      UPDATE marketing_report_comparisons SET status='ready',as_of=now(),data=$2::jsonb,
        updated_at=now() WHERE id=$1 AND status='pending'
      """,
      [comparison.id, Jason.encode!(data)]
    )
  end

  defp decode_json(value) when is_binary(value), do: Jason.decode!(value)
  defp decode_json(value) when is_map(value), do: value

  defp normalize_filters(policy, filters) do
    today = Date.utc_today()
    from_on = parse_date(Map.get(filters, :from, Map.get(filters, "from")), Date.add(today, -89))
    to_on = parse_date(Map.get(filters, :to, Map.get(filters, "to")), today)
    branch = Map.get(filters, :branch_id, Map.get(filters, "branch_id"))
    branch_key = if is_nil(branch) or branch == "", do: "all", else: branch

    valid_branch =
      branch_key == "all" or
        (match?({:ok, _}, Ecto.UUID.cast(branch_key)) and branch_in_policy?(policy, branch_key))

    if match?(%Date{}, from_on) and match?(%Date{}, to_on) and
         Date.compare(from_on, to_on) != :gt and Date.diff(to_on, from_on) < @max_days and
         Date.compare(to_on, today) != :gt and valid_branch,
       do: {:ok, from_on, to_on, branch_key},
       else: {:error, :invalid_report_filters}
  end

  defp parse_date(nil, default), do: default
  defp parse_date(%Date{} = date, _), do: date

  defp parse_date(value, _) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> :invalid
    end
  end

  defp parse_date(_, _), do: :invalid

  defp branch_in_policy?(%Policy{scope: :franchise}, branch_id) do
    Repo.exists?(
      from b in Delivest.Identity.Branch,
        where: b.id == ^branch_id and is_nil(b.deleted_at)
    )
  end

  defp branch_in_policy?(%Policy{id: policy_id}, branch_id) do
    Repo.exists?(
      from b in "marketing_policy_branches",
        where:
          b.policy_id == type(^policy_id, :binary_id) and
            b.branch_id == type(^branch_id, :binary_id)
    )
  end

  defp public_result(id, status, as_of, data) do
    ready? = status == "ready"

    %{
      id: Ecto.UUID.load!(id),
      status: if(ready?, do: :ready, else: :pending),
      as_of: if(ready? and as_of, do: DateTime.from_naive!(as_of, "Etc/UTC"), else: nil),
      data: if(ready?, do: if(is_binary(data), do: Jason.decode!(data), else: data), else: nil)
    }
  end
end
