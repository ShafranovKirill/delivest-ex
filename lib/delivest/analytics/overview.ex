defmodule Delivest.Analytics.Overview do
  import Ecto.Query

  @moduledoc """
  Authorized statistics overview. A sale belongs to the local date on which its
  completed order was created. Successful refunds, including later refunds,
  reduce that order's original sales day. This matches the F04 revenue cohort.
  """

  alias Delivest.{Features, Identity, LocalTime, Repo}
  alias Delivest.Identity.Branch.FulfillmentSettings
  alias Delivest.Oms.OrderSource
  alias Delivest.Analytics.Reports

  @max_days 366
  @report_tabs ~w(funnel sources customers channels comparison)

  def read(staff, scope, period, opts \\ [])

  def read(staff, scope, {from, to} = period, opts) do
    with :ok <- authorize_period(from, to),
         {:ok, branches} <- branches(staff, scope) do
      ids = Enum.map(branches, & &1.id)

      zone =
        if match?({:branch, _}, scope),
          do: LocalTime.timezone(hd(ids)),
          else: LocalTime.timezone()

      {rows, updated_at, stale?} = read_daily(ids, period)
      summary = rows |> Enum.map(& &1.metrics) |> sum_metrics()
      daily = days(rows, period)
      clients = read_clients(ids, period, summary.orders_count)

      clients =
        if stale?,
          do: %{
            new: nil,
            returning: nil,
            identified_orders: nil,
            total_orders: nil,
            coverage: nil
          },
          else: clients

      visibility = visibility(branches)

      comparison =
        comparison(
          ids,
          Keyword.get(opts, :comparison_period),
          period,
          zone,
          Keyword.get(opts, :now, DateTime.utc_now())
        )

      {:ok,
       %{
         summary: summary,
         daily: daily,
         clients: clients,
         quality: %{on_time_rate: nil, coverage: nil, reason: :missing_timestamps},
         branches: branch_rows(branches, rows),
         visibility: visibility,
         updated_at: updated_at,
         timezone: zone,
         comparison: comparison,
         state:
           if(stale?, do: :partial, else: if(summary.orders_count == 0, do: :empty, else: :ready))
       }}
    end
  end

  def read(_, _, _, _), do: {:error, :invalid_period}

  def details(staff, scope, period, kind),
    do: Delivest.Analytics.OverviewDetails.read(staff, scope, period, kind)

  def orders(staff, scope, period, kind, opts \\ []),
    do: Delivest.Analytics.OverviewDetails.orders(staff, scope, period, kind, opts)

  @doc false
  def valid_period({from, to}), do: authorize_period(from, to)
  def valid_period(_), do: {:error, :invalid_period}

  @doc false
  def authorized_branches(staff, scope), do: branches(staff, scope)

  @doc false
  def allowed_sources(ids) when is_list(ids) do
    Delivest.Identity.Branch
    |> where([b], b.id in ^ids and is_nil(b.deleted_at))
    |> preload(:info)
    |> Repo.all()
    |> Enum.map(fn branch ->
      settings = branch.info && branch.info.channels

      external =
        if settings && settings.yandex_eda && settings.yandex_eda.enabled,
          do: ["yandex_eda"],
          else: []

      {branch.id, OrderSource.own() ++ external}
    end)
    |> Map.new()
  end

  defp authorize_period(%Date{} = from, %Date{} = to) do
    days = Date.diff(to, from) + 1
    if days in 1..@max_days, do: :ok, else: {:error, :invalid_period}
  end

  defp authorize_period(_, _), do: {:error, :invalid_period}

  defp branches(staff, {:branch, id}) do
    with :ok <- Identity.authorize(staff, "statistics.read", id),
         branch when not is_nil(branch) <-
           Enum.find(Identity.list_branch_for_staff(staff, preload: :info), &(&1.id == id)) do
      {:ok, [branch]}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp branches(staff, :network) do
    if Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network") do
      {:ok, Identity.list_branch_for_staff(staff, preload: :info)}
    else
      {:error, :forbidden}
    end
  end

  defp branches(_, _), do: {:error, :forbidden}

  @doc false
  def day_payload(id, day) do
    metrics =
      [id]
      |> raw_daily({day, day})
      |> Enum.find_value(
        %{revenue: 0, orders_count: 0, cancelled_count: 0, refund_amount: 0, refund_count: 0},
        & &1.metrics
      )

    Map.put(metrics, :version, 1)
  end

  defp read_daily([], _), do: {[], nil, false}

  defp read_daily(ids, {from, to}) do
    zones =
      Repo.query!(
        "SELECT b.id::text,COALESCE(i.timezone,fs.timezone,'Europe/Moscow') " <>
          "FROM unnest($1::uuid[]) b(id) LEFT JOIN branch_info i ON i.branch_id=b.id " <>
          "CROSS JOIN (SELECT timezone FROM franchise_settings LIMIT 1) fs",
        [Enum.map(ids, &Ecto.UUID.dump!/1)]
      ).rows

    cached =
      Repo.query!(
        "SELECT branch_id::text,day,timezone,dirty,payload->'overview',computed_at FROM sales_daily_rollups " <>
          "WHERE branch_id=ANY($1::uuid[]) AND day BETWEEN $2 AND $3",
        [Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
      ).rows
      |> Map.new(fn [id, day, zone, dirty, payload, at] ->
        {{id, day}, {zone, dirty, payload, at}}
      end)

    keys = for [id, zone] <- zones, day <- Date.range(from, to), do: {id, day, zone}

    {published, missing, dirty_days, current, stale?} =
      Enum.reduce(keys, {[], [], [], [], false}, fn {id, day, zone} = key,
                                                    {pub, miss, dirty_days, cur, stale} ->
        if Date.before?(day, LocalTime.today(zone)) do
          case cached[{id, day}] do
            {^zone, dirty, %{"version" => 1} = payload, at} ->
              row = %{branch_id: id, day: day, metrics: payload_metrics(payload), computed_at: at}

              {[row | pub], miss, if(dirty, do: [key | dirty_days], else: dirty_days), cur,
               stale or dirty}

            _ ->
              {pub, [key | miss], dirty_days, cur, true}
          end
        else
          {pub, miss, dirty_days, [key | cur], stale}
        end
      end)

    if missing != [] or dirty_days != [], do: queue_rebuild(missing ++ dirty_days)
    # Current local days are live; historical days are read from published rollups.
    # Historical gaps stay explicitly partial until the worker publishes them.
    source = current
    source_ids = source |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    source_days = Enum.map(source, &elem(&1, 1))

    source_rows =
      if source == [],
        do: [],
        else: raw_daily(source_ids, {Enum.min(source_days), Enum.max(source_days)})

    source_set = MapSet.new(Enum.map(source, fn {id, day, _} -> {id, day} end))
    source_rows = Enum.filter(source_rows, &MapSet.member?(source_set, {&1.branch_id, &1.day}))
    published_times = Enum.map(published, & &1.computed_at) |> Enum.reject(&is_nil/1)

    updated_at =
      cond do
        published_times != [] ->
          published_times
          |> Enum.min_by(&NaiveDateTime.to_gregorian_seconds/1)
          |> DateTime.from_naive!("Etc/UTC")

        source != [] ->
          DateTime.utc_now()

        true ->
          nil
      end

    {published ++ source_rows, updated_at, stale? or missing != []}
  end

  defp payload_metrics(payload) do
    Map.new(~w(revenue orders_count cancelled_count refund_amount refund_count), fn key ->
      {String.to_existing_atom(key), payload[key] || 0}
    end)
  end

  defp queue_rebuild(keys) do
    {ids, days} =
      keys
      |> Enum.uniq_by(fn {id, day, _} -> {id, day} end)
      |> Enum.map(fn {id, day, _} -> {Ecto.UUID.dump!(id), day} end)
      |> Enum.unzip()

    Repo.query!(
      "INSERT INTO sales_daily_rollups(branch_id,day,dirty) " <>
        "SELECT id,day,true FROM unnest($1::uuid[],$2::date[]) AS wanted(id,day) " <>
        "ON CONFLICT (branch_id,day) DO UPDATE SET dirty=true",
      [ids, days]
    )

    %{} |> Delivest.Analytics.SalesCacheWorker.new() |> Oban.insert()
  end

  defp raw_daily(ids, period, cutoff \\ nil)

  defp raw_daily([], _, _), do: []

  defp raw_daily(ids, {from, to}, cutoff) do
    Repo.query!(
      """
      WITH scoped AS (
        SELECT o.id,o.branch_id,o.status,o.total_amount,
          COALESCE(bi.timezone,fs.timezone,'Europe/Moscow') AS zone,
          timezone(COALESCE(bi.timezone,fs.timezone,'Europe/Moscow'),timezone('UTC',o.inserted_at)) AS local_at,
          (timezone(COALESCE(bi.timezone,fs.timezone,'Europe/Moscow'),timezone('UTC',o.inserted_at)))::date AS local_day
        FROM orders o
        LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
        CROSS JOIN (SELECT timezone FROM franchise_settings LIMIT 1) fs
        WHERE o.branch_id=ANY($1::uuid[]) AND o.deleted_at IS NULL
          AND o.inserted_at >= ($2::date - interval '1 day')
          AND o.inserted_at < ($3::date + interval '2 days')
      ), refunds AS (
        SELECT f.order_id,sum(f.amount)::bigint amount,count(*)::bigint n
        FROM order_refunds f JOIN scoped s ON s.id=f.order_id
        WHERE f.status='succeeded' GROUP BY f.order_id
      )
      SELECT s.branch_id::text,s.local_day,
        COALESCE(sum(GREATEST(s.total_amount-COALESCE(f.amount,0),0))
          FILTER (WHERE s.status='completed'),0)::bigint revenue,
        count(*) FILTER (WHERE s.status='completed')::bigint completed,
        count(*) FILTER (WHERE s.status='cancelled')::bigint cancelled,
        COALESCE(sum(LEAST(s.total_amount,COALESCE(f.amount,0)))
          FILTER (WHERE s.status='completed'),0)::bigint refund_amount,
        COALESCE(sum(f.n) FILTER (WHERE s.status='completed'),0)::bigint refund_count
      FROM scoped s LEFT JOIN refunds f ON f.order_id=s.id
      WHERE s.local_day BETWEEN $2::date AND $3::date
        AND ($4::timestamptz IS NULL OR s.local_day < $3::date OR
          s.local_at::time <= timezone(s.zone,$4::timestamptz)::time)
      GROUP BY s.branch_id,s.local_day ORDER BY s.local_day,s.branch_id
      """,
      [Enum.map(ids, &Ecto.UUID.dump!/1), from, to, cutoff]
    ).rows
    |> Enum.map(fn [id, day, revenue, completed, cancelled, refund_amount, refund_count] ->
      %{
        branch_id: id,
        day: day,
        metrics: %{
          revenue: revenue,
          orders_count: completed,
          cancelled_count: cancelled,
          refund_amount: refund_amount,
          refund_count: refund_count
        }
      }
    end)
  end

  defp sum_metrics(rows) do
    total =
      Enum.reduce(
        rows,
        %{revenue: 0, orders_count: 0, cancelled_count: 0, refund_amount: 0, refund_count: 0},
        fn row, acc ->
          Map.merge(acc, row, fn _, a, b -> a + b end)
        end
      )

    denominator = total.orders_count + total.cancelled_count

    total
    |> Map.put(
      :avg_check,
      if(total.orders_count > 0, do: round(total.revenue / total.orders_count), else: 0)
    )
    |> Map.put(
      :cancellation_rate,
      if(denominator > 0,
        do: Float.round(100 * total.cancelled_count / denominator, 1),
        else: nil
      )
    )
  end

  defp days(rows, {from, to}) do
    grouped = Enum.group_by(rows, & &1.day, & &1.metrics)

    for day <- Date.range(from, to) do
      total = grouped |> Map.get(day, []) |> sum_metrics()
      %{date: day, revenue: total.revenue, orders: total.orders_count}
    end
  end

  defp branch_rows(branches, rows) do
    grouped = Enum.group_by(rows, & &1.branch_id, & &1.metrics)

    Enum.map(branches, fn branch ->
      total = grouped |> Map.get(branch.id, []) |> sum_metrics()
      Map.merge(%{id: branch.id, name: branch.name}, total)
    end)
  end

  defp read_clients([], _, total),
    do: %{new: 0, returning: 0, identified_orders: 0, total_orders: total, coverage: nil}

  defp read_clients(ids, {from, to}, total) do
    [[identified, new, returning]] =
      Repo.query!(
        """
        WITH scoped AS (
          SELECT o.id,o.inserted_at,r.verified_client_id,
            COALESCE(bi.timezone,fs.timezone,'Europe/Moscow') AS zone,
          timezone(COALESCE(bi.timezone,fs.timezone,'Europe/Moscow'),timezone('UTC',o.inserted_at)) AS local_at,
          (timezone(COALESCE(bi.timezone,fs.timezone,'Europe/Moscow'),timezone('UTC',o.inserted_at)))::date AS local_day
          FROM orders o JOIN analytics_order_identities r ON r.order_id=o.id
          LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
          CROSS JOIN (SELECT timezone FROM franchise_settings LIMIT 1) fs
          WHERE o.branch_id=ANY($1::uuid[]) AND o.deleted_at IS NULL
            AND o.status='completed' AND r.verified_client_id IS NOT NULL
        ), period_clients AS (
          SELECT verified_client_id,min(inserted_at) first_in_period,count(*) orders
          FROM scoped WHERE local_day BETWEEN $2::date AND $3::date GROUP BY verified_client_id
        ), first_orders AS (
          SELECT verified_client_id,min(inserted_at) first_ever
          FROM scoped WHERE verified_client_id IN (SELECT verified_client_id FROM period_clients)
          GROUP BY verified_client_id
        )
        SELECT COALESCE(sum(p.orders),0)::bigint,
          count(*) FILTER (WHERE p.first_in_period=f.first_ever)::bigint,
          count(*) FILTER (WHERE p.first_in_period<>f.first_ever)::bigint
        FROM period_clients p JOIN first_orders f USING (verified_client_id)
        """,
        [Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
      ).rows

    %{
      new: new,
      returning: returning,
      identified_orders: identified,
      total_orders: total,
      coverage: if(total > 0, do: Float.round(100 * identified / total, 1), else: nil)
    }
  end

  defp visibility(branches) do
    ids = Enum.map(branches, & &1.id)

    flags =
      Features.enabled_branches_many(Enum.map(@report_tabs, &Reports.feature_for_tab/1), ids)

    reports =
      Enum.filter(@report_tabs, fn tab ->
        feature = Reports.feature_for_tab(tab)
        Enum.any?(ids, &MapSet.member?(flags[feature], &1))
      end)

    fulfillment =
      branches
      |> Enum.flat_map(fn branch ->
        settings = branch.info && branch.info.fulfillment
        FulfillmentSettings.enabled(settings)
      end)
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    external =
      branches
      |> Enum.flat_map(fn branch ->
        settings = branch.info && branch.info.channels

        if settings && settings.yandex_eda && settings.yandex_eda.enabled,
          do: ["yandex_eda"],
          else: []
      end)
      |> Enum.uniq()

    destinations =
      branches
      |> Enum.flat_map(fn branch ->
        crm = branch.info && branch.info.crm
        if crm && crm.enabled && crm.provider, do: [to_string(crm.provider)], else: []
      end)
      |> Enum.uniq()

    %{
      reports: reports,
      fulfillment: fulfillment,
      channels: OrderSource.own() ++ external,
      destinations: destinations
    }
  end

  defp comparison(_, nil, _, _, _), do: nil

  defp comparison(
         ids,
         {%Date{} = from, %Date{} = to} = period,
         {_selected_from, selected_to},
         zone,
         now
       ) do
    if authorize_period(from, to) == :ok do
      {rows, _, stale?} = read_daily(ids, period)
      elapsed? = selected_to == LocalTime.today(zone) and Date.before?(to, selected_to)

      rows =
        if elapsed? do
          partial = raw_daily(ids, {to, to}, now)
          Enum.reject(rows, &(&1.day == to)) ++ partial
        else
          rows
        end

      %{
        period: period,
        summary: rows |> Enum.map(& &1.metrics) |> sum_metrics(),
        daily: days(rows, period),
        state: if(stale?, do: :partial, else: :ready),
        cutoff:
          if(elapsed?,
            do: now |> DateTime.shift_zone!(zone) |> DateTime.to_time() |> Time.truncate(:second),
            else: nil
          )
      }
    end
  end

  defp comparison(_, _, _, _, _), do: nil
end
