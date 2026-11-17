defmodule Delivest.Integrations.YandexAds.Campaigns do
  @moduledoc """
  Explicit mappings from internal trusted advertising links to imported Direct campaigns.

  A mapping is a current reporting configuration: changing it reclassifies historical
  immutable link receipts. It does not turn browser-supplied campaign labels into
  trusted attribution or prove incremental sales caused by advertising.
  """
  import Ecto.Query
  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Advertising.Link
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.Cost
  alias Delivest.Analytics.Reports

  @warning "Current server mappings apply to historical trusted link receipts; attributed revenue is not causal uplift."

  def bind(staff, link_id, campaign_id) do
    with true <- Identity.can?(staff, "admin"),
         {:ok, link_id} <- Ecto.UUID.cast(link_id),
         true <- is_binary(campaign_id) and Regex.match?(~r/^[1-9][0-9]{0,29}$/, campaign_id) do
      Repo.transaction(fn ->
        YandexAds.lock_settings()
        account = YandexAds.account_key(YandexAds.get_settings())
        link = active_link(link_id)

        if is_nil(link) or not known_campaign?(account, campaign_id),
          do: Repo.rollback(:unknown_link_or_campaign)

        Repo.query!(
          """
          INSERT INTO yandex_ads_campaign_bindings
            (account_scope,advertising_link_id,campaign_id,bound_by_id,inserted_at,updated_at)
          VALUES ($1,$2::text::uuid,$3,$4::text::uuid,$5,$5)
          ON CONFLICT (account_scope,advertising_link_id)
          DO UPDATE SET campaign_id=EXCLUDED.campaign_id,bound_by_id=EXCLUDED.bound_by_id,
            updated_at=EXCLUDED.updated_at
          """,
          [account, link_id, campaign_id, staff.id, YandexAds.now()]
        )

        Audit.record(staff, "integration.yandex_campaign_bound", link,
          metadata: %{account_scope: account, campaign_id: campaign_id}
        )

        %{account_scope: account, advertising_link_id: link_id, campaign_id: campaign_id}
      end)
    else
      _ -> {:error, :forbidden_or_invalid_binding}
    end
  end

  def unbind(staff, link_id) do
    with true <- Identity.can?(staff, "admin"), {:ok, link_id} <- Ecto.UUID.cast(link_id) do
      Repo.transaction(fn ->
        YandexAds.lock_settings()
        account = YandexAds.account_key(YandexAds.get_settings())
        link = Repo.get(Link, link_id)
        if is_nil(link), do: Repo.rollback(:unknown_link)

        Repo.query!(
          "DELETE FROM yandex_ads_campaign_bindings WHERE account_scope=$1 AND advertising_link_id=$2::text::uuid",
          [account, link_id]
        )

        Audit.record(staff, "integration.yandex_campaign_unbound", link,
          metadata: %{account_scope: account}
        )

        :removed
      end)
    else
      _ -> {:error, :forbidden_or_invalid_binding}
    end
  end

  def list(staff, opts \\ []) do
    with true <- network_read?(staff), {:ok, {limit, offset}} <- pagination(opts) do
      account = YandexAds.account_key(YandexAds.get_settings())

      result =
        Repo.query!(
          """
          SELECT b.advertising_link_id::text,b.campaign_id,l.name,l.campaign,l.branch_id::text,
            b.updated_at,COUNT(*) OVER()::bigint
          FROM yandex_ads_campaign_bindings b JOIN advertising_links l ON l.id=b.advertising_link_id
          WHERE b.account_scope=$1 ORDER BY b.updated_at DESC,b.advertising_link_id
          LIMIT $2 OFFSET $3
          """,
          [account, limit, offset]
        )

      bindings =
        for [id, campaign, name, label, branch_id, updated_at, _] <- result.rows,
            do: %{
              advertising_link_id: id,
              campaign_id: campaign,
              link_name: name,
              link_campaign: label,
              branch_id: branch_id,
              updated_at: updated_at
            }

      total =
        case result.rows do
          [[_, _, _, _, _, _, count] | _] ->
            count

          [] ->
            %{rows: [[count]]} =
              Repo.query!(
                "SELECT COUNT(*)::bigint FROM yandex_ads_campaign_bindings WHERE account_scope=$1",
                [account]
              )

            count
        end

      {:ok,
       %{
         bindings: bindings,
         total: total,
         has_more: total > offset + length(bindings),
         limit: limit,
         offset: offset
       }}
    else
      _ -> {:error, :forbidden_or_invalid_page}
    end
  end

  def options(staff, search \\ "") do
    if network_read?(staff) and is_binary(search) do
      account = YandexAds.account_key(YandexAds.get_settings())
      term = "%" <> String.slice(search, 0, 80) <> "%"

      links =
        Repo.query!(
          """
          SELECT l.id::text,l.name,l.campaign,l.branch_id::text FROM advertising_links l
          JOIN branches b ON b.id=l.branch_id
          WHERE l.archived_at IS NULL AND b.deleted_at IS NULL AND
            (l.name ILIKE $1 OR l.campaign ILIKE $1 OR l.id::text ILIKE $1)
          ORDER BY l.name,l.id LIMIT 50
          """,
          [term]
        ).rows

      campaigns =
        Repo.query!(
          """
          SELECT campaign_id,MAX(campaign_name) FROM yandex_ads_costs
          WHERE account=$1 AND (campaign_id ILIKE $2 OR campaign_name ILIKE $2)
          GROUP BY campaign_id ORDER BY campaign_id LIMIT 50
          """,
          [account, term]
        ).rows

      {:ok,
       %{
         links:
           Enum.map(links, fn [id, name, campaign, branch] ->
             %{id: id, name: name, campaign: campaign, branch_id: branch}
           end),
         campaigns:
           Enum.map(campaigns, fn [id, name] -> %{campaign_id: id, campaign_name: name} end)
       }}
    else
      {:error, :forbidden}
    end
  end

  def report(staff, from, to, opts \\ [])

  def report(staff, %Date{} = from, %Date{} = to, opts) do
    with true <- network_read?(staff),
         true <- Date.diff(to, from) in 0..366,
         {:ok, {limit, offset}} <- pagination(opts) do
      ids = Repo.all(from(b in Branch, where: is_nil(b.deleted_at), select: b.id))

      # Daily source staging owns its repeatable-read transaction. Keep it outside
      # the advertiser settings lock; link buckets do not belong to an ad account.
      with {:ok, f04} <- Reports.read_link_scope(staff, ids, {from, to}) do
        Repo.transaction(fn ->
          YandexAds.lock_settings()
          settings = YandexAds.get_settings()

          result =
            Repo.query!(report_sql(), [
              YandexAds.account_key(settings),
              from,
              to,
              Enum.map(f04.branch_ids, &Ecto.UUID.dump!/1),
              limit,
              offset
            ])

          cost_period_complete = cost_period_complete?(settings, from, to)

          campaigns =
            Enum.map(
              result.rows,
              &campaign_row(&1, Map.put(f04, :cost_period_complete, cost_period_complete))
            )

          total =
            case result.rows do
              [row | _] ->
                List.last(row)

              [] ->
                %{rows: [[count]]} =
                  Repo.query!(
                    """
                    SELECT COUNT(*)::bigint FROM (
                      SELECT campaign_id FROM yandex_ads_costs WHERE account=$1 AND day BETWEEN $2 AND $3
                      UNION SELECT campaign_id FROM yandex_ads_campaign_bindings WHERE account_scope=$1
                    ) campaigns
                    """,
                    [YandexAds.account_key(settings), from, to]
                  )

                count
            end

          %{
            campaigns: campaigns,
            total_campaigns: total,
            truncated: total > offset + length(campaigns),
            limit: limit,
            offset: offset,
            coverage: "trusted_internal_links_current_mapping",
            warning: @warning,
            order_period: "branch_local_order_creation_date",
            cost_period: "direct_campaign_report_date",
            cost_timezone: settings.timezone,
            cost_period_complete: cost_period_complete,
            f04_state: f04.state,
            refresh_pending: Map.get(f04, :refresh_pending, false),
            covered_days: f04.covered_days,
            expected_days: f04.expected_days,
            excluded_branches: f04.excluded_branches,
            last_success_at: f04.last_success_at,
            last_checked_at: f04.last_checked_at
          }
        end)
      end
    else
      _ -> {:error, :forbidden_or_invalid_period}
    end
  end

  def report(_, _, _, _), do: {:error, :invalid_period}

  defp campaign_row(
         [
           id,
           name,
           currency,
           vat,
           cost,
           cost_rows,
           mappings,
           orders,
           revenue,
           mixed,
           _total
         ],
         f04
       ) do
    available = f04.state != :not_collected
    complete = f04.excluded_branches == 0 and f04.covered_days == f04.expected_days and available

    comparable =
      complete and not Map.get(f04, :refresh_pending, false) and f04.cost_period_complete and
        not mixed and cost_rows > 0 and mappings > 0 and cost > 0

    %{
      campaign_id: id,
      campaign_name: name,
      currency: currency,
      include_vat: vat,
      cost_micros: if(mixed, do: nil, else: cost),
      cost_available: cost_rows > 0,
      mapping_count: mappings,
      completed_orders: if(available, do: orders),
      net_revenue: if(available, do: revenue),
      f04_state: f04.state,
      roas: if(comparable, do: Decimal.div(Decimal.new(revenue * 10_000), Decimal.new(cost))),
      cpa_micros:
        if(comparable and orders > 0, do: Decimal.div(Decimal.new(cost), Decimal.new(orders))),
      reason:
        cond do
          not available -> "f04_not_collected"
          not complete -> "f04_partial_coverage"
          not f04.cost_period_complete -> "cost_period_incomplete"
          mixed -> "mixed_cost_basis"
          cost_rows == 0 -> "costs_not_collected_for_period"
          mappings == 0 -> "trusted_mapping_missing"
          cost == 0 -> "zero_cost"
          orders == 0 -> "no_trusted_completed_orders"
          true -> nil
        end
    }
  end

  defp active_link(id) do
    Repo.one(
      from(l in Link,
        join: b in Branch,
        on: b.id == l.branch_id,
        where: l.id == ^id and is_nil(l.archived_at) and is_nil(b.deleted_at),
        select: l
      )
    )
  end

  defp known_campaign?(account, campaign),
    do: Repo.exists?(from(c in Cost, where: c.account == ^account and c.campaign_id == ^campaign))

  defp network_read?(staff),
    do: YandexAds.account_report_authorized?(staff)

  defp cost_period_complete?(
         %{
           costs_refreshed_at: %DateTime{},
           costs_from: %Date{} = start,
           costs_to: %Date{} = finish
         },
         from,
         to
       ),
       do: Date.compare(start, from) != :gt and Date.compare(finish, to) != :lt

  defp cost_period_complete?(_, _, _), do: false

  defp pagination(opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    if is_integer(limit) and limit in 1..250 and is_integer(offset) and offset in 0..100_000,
      do: {:ok, {limit, offset}},
      else: {:error, :invalid_page}
  end

  defp pagination(_), do: {:error, :invalid_page}

  defp report_sql do
    """
    WITH latest_costs AS (
      SELECT DISTINCT ON (day,campaign_id) * FROM yandex_ads_costs
      WHERE account=$1 AND day BETWEEN $2 AND $3
      ORDER BY day,campaign_id,updated_at DESC,generation DESC
    ), costs AS (
      SELECT campaign_id,MAX(campaign_name) AS name,MIN(currency) AS currency,
        BOOL_AND(include_vat) AS vat,SUM(cost_micros)::bigint AS cost,COUNT(*)::bigint AS rows,
        COUNT(DISTINCT currency)>1 OR COUNT(DISTINCT include_vat)>1 AS mixed
      FROM latest_costs GROUP BY campaign_id
    ), bindings AS (
      SELECT * FROM yandex_ads_campaign_bindings WHERE account_scope=$1
    ), mappings AS (
      SELECT campaign_id,COUNT(*)::bigint AS count FROM bindings GROUP BY campaign_id
    ), revenue AS (
      SELECT b.campaign_id,
        COALESCE(SUM((r.counts->>'completed')::bigint),0)::bigint AS orders,
        COALESCE(SUM((r.counts->>'revenue')::bigint),0)::bigint AS net
      FROM analytics_report_states s JOIN analytics_report_rows r ON r.snapshot_id=s.snapshot_id
      JOIN bindings b ON b.advertising_link_id::text=r.key
      WHERE s.feature='analytics_links' AND s.branch_id=ANY($4::uuid[])
        AND s.day BETWEEN $2 AND $3 AND r.dimension='link'
      GROUP BY b.campaign_id
    ), keys AS (
      SELECT campaign_id FROM costs UNION SELECT campaign_id FROM mappings
    )
    SELECT k.campaign_id,COALESCE(c.name,k.campaign_id),c.currency,c.vat,COALESCE(c.cost,0)::bigint,
      COALESCE(c.rows,0)::bigint,COALESCE(m.count,0)::bigint,COALESCE(r.orders,0)::bigint,
      COALESCE(r.net,0)::bigint,COALESCE(c.mixed,false),COUNT(*) OVER()::bigint
    FROM keys k LEFT JOIN costs c ON c.campaign_id=k.campaign_id
    LEFT JOIN mappings m ON m.campaign_id=k.campaign_id
    LEFT JOIN revenue r ON r.campaign_id=k.campaign_id
    ORDER BY k.campaign_id LIMIT $5 OFFSET $6
    """
  end
end
