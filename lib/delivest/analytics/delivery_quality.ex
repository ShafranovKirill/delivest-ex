defmodule Delivest.Analytics.DeliveryQuality do
  @moduledoc """
  Completed delivery orders by branch-local *creation* date. Rates are numeric
  percentages (0..100); on-time denominator is measured, coverage denominator
  is total. The deadline comparison includes equality. No customer/order PII.
  """
  alias Delivest.{Analytics.Overview, Repo}

  def read(staff, scope, period) do
    with :ok <- Overview.valid_period(period),
         {:ok, branches} <- Overview.authorized_branches(staff, scope) do
      rows = query(Enum.map(branches, & &1.id), period)

      by_day =
        Map.new(rows, fn [day, total, measured, on_time] ->
          {day, metrics(total, measured, on_time)}
        end)

      {from, to} = period

      daily =
        Enum.map(Date.range(from, to), fn day ->
          Map.put(Map.get(by_day, day, metrics(0, 0, 0)), :date, day)
        end)

      total = Enum.sum(Enum.map(daily, & &1.total))
      measured = Enum.sum(Enum.map(daily, & &1.measured))
      on_time = Enum.sum(Enum.map(daily, & &1.on_time))
      {:ok, %{summary: metrics(total, measured, on_time), daily: daily}}
    end
  end

  def detail(staff, scope, period, %Date{} = day) do
    with :ok <- Overview.valid_period(period),
         {from, to} <- period,
         true <-
           (Date.compare(day, from) != :lt and Date.compare(day, to) != :gt) ||
             {:error, :invalid_day},
         {:ok, branches} <- Overview.authorized_branches(staff, scope) do
      row = query(Enum.map(branches, & &1.id), {day, day})
      [_, total, measured, on_time] = List.first(row) || [day, 0, 0, 0]
      {:ok, Map.put(metrics(total, measured, on_time), :date, day)}
    else
      false -> {:error, :invalid_day}
      error -> error
    end
  end

  def detail(_, _, _, _), do: {:error, :invalid_day}

  defp metrics(total, measured, on_time) do
    %{
      total: total,
      measured: measured,
      on_time: on_time,
      late: measured - on_time,
      missing: total - measured,
      on_time_rate: if(measured == 0, do: nil, else: 100.0 * on_time / measured),
      coverage: if(total == 0, do: nil, else: 100.0 * measured / total),
      reason: if(measured == 0, do: :missing_timestamps, else: nil)
    }
  end

  defp query([], _period), do: []

  defp query(ids, {from, to}) do
    Repo.query!(
      """
      WITH scoped AS (
        SELECT o.initial_promised_delivery_at,o.delivered_at,
          (o.initial_promised_delivery_at IS NOT NULL AND o.delivered_at IS NOT NULL
           AND o.delivery_actual_source IN ('staff_handover','yandex_delivery')
           AND EXISTS (
             SELECT 1 FROM delivery_promise_history h
             WHERE h.order_id=o.id AND h.source='staff'
               AND h.promised_at=o.initial_promised_delivery_at
           )
           AND EXISTS (
             SELECT 1 FROM delivery_actual_events e
             WHERE e.order_id=o.id AND e.source=o.delivery_actual_source
               AND e.occurred_at=o.delivered_at
           )) AS measured,
          timezone(COALESCE(bi.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow'),
                   timezone('UTC',o.inserted_at))::date AS local_day
        FROM orders o
        LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
        WHERE o.branch_id=ANY($1::uuid[]) AND o.deleted_at IS NULL
          AND o.status='completed' AND o.fulfillment_type='delivery'
          AND o.inserted_at >= ($2::date - interval '1 day')
          AND o.inserted_at < ($3::date + interval '2 days')
      )
      SELECT local_day,count(*)::bigint,
        count(*) FILTER (WHERE measured)::bigint,
        count(*) FILTER (WHERE measured AND delivered_at <= initial_promised_delivery_at)::bigint
      FROM scoped WHERE local_day BETWEEN $2::date AND $3::date
      GROUP BY local_day ORDER BY local_day
      """,
      [Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
    ).rows
  end
end
