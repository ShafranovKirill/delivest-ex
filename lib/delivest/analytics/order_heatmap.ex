defmodule Delivest.Analytics.OrderHeatmap do
  @moduledoc """
  Created orders by branch-local weekday and hour. Network totals sum local
  buckets, while the denominator is the number of calendar dates, not branches.
  """
  alias Delivest.{Analytics.Overview, LocalTime, Repo}

  @fulfillments ~w(all delivery pickup dine_in)

  def default_period(scope) do
    zone =
      case scope do
        {:branch, id} -> LocalTime.timezone(id)
        _ -> LocalTime.timezone()
      end

    monday = Date.beginning_of_week(LocalTime.today(zone), :monday)
    {Date.add(monday, -28), Date.add(monday, -1)}
  end

  def valid_period({%Date{} = from, %Date{} = to}) do
    days = Date.diff(to, from) + 1

    if Date.day_of_week(from) == 1 and Date.day_of_week(to) == 7 and
         days in 7..364 and rem(days, 7) == 0,
       do: :ok,
       else: {:error, :invalid_period}
  end

  def valid_period(_), do: {:error, :invalid_period}

  def read(staff, scope, period, fulfillment \\ "all", branch_id \\ nil) do
    with :ok <- valid_period(period),
         :ok <- valid_fulfillment(fulfillment),
         {:ok, branches} <- Overview.authorized_branches(staff, scope),
         {:ok, selected} <- select_branches(scope, branches, branch_id) do
      dates = weekday_dates(period)
      counts = query(Enum.map(selected, & &1.id), period, fulfillment)
      totals = Map.new(counts, fn {day, hour, total} -> {{day, hour}, total} end)

      cells =
        for day <- 1..7, hour <- 0..23 do
          total = Map.get(totals, {day, hour}, 0)

          %{
            day: day,
            hour: hour,
            total: total,
            dates: length(Map.fetch!(dates, day)),
            average: total / length(Map.fetch!(dates, day))
          }
        end

      {:ok,
       %{
         cells: cells,
         branches: branches,
         period: period,
         fulfillment: fulfillment,
         state:
           if(branches == [],
             do: :no_branches,
             else: if(Enum.all?(cells, &(&1.total == 0)), do: :empty, else: :ready)
           )
       }}
    end
  end

  def detail(staff, scope, period, fulfillment, day, hour, branch_id \\ nil) do
    with :ok <- valid_period(period),
         :ok <- valid_fulfillment(fulfillment),
         true <- (day in 1..7 and hour in 0..23) || {:error, :invalid_cell},
         {:ok, branches} <- Overview.authorized_branches(staff, scope),
         {:ok, selected} <- select_branches(scope, branches, branch_id) do
      dates = Map.fetch!(weekday_dates(period), day)
      rows = query(Enum.map(selected, & &1.id), period, fulfillment, :daily)
      counts = Map.new(rows, fn {date, h, count} -> {{date, h}, count} end)
      {:ok, Enum.map(dates, &%{date: &1, total: Map.get(counts, {&1, hour}, 0)})}
    else
      false -> {:error, :invalid_cell}
      error -> error
    end
  end

  defp select_branches({:branch, _}, branches, nil), do: {:ok, branches}
  defp select_branches(:network, branches, nil), do: {:ok, branches}

  defp select_branches(:network, branches, id) when is_binary(id) do
    case Enum.find(branches, &(&1.id == id)) do
      nil -> {:error, :forbidden}
      branch -> {:ok, [branch]}
    end
  end

  defp select_branches(_, _, _), do: {:error, :forbidden}

  defp valid_fulfillment(value) when value in @fulfillments, do: :ok
  defp valid_fulfillment(_), do: {:error, :invalid_fulfillment}

  defp weekday_dates({from, to}) do
    dates = Enum.to_list(Date.range(from, to))
    Map.new(1..7, fn day -> {day, Enum.filter(dates, &(Date.day_of_week(&1) == day))} end)
  end

  defp query(ids, period, fulfillment), do: query(ids, period, fulfillment, :weekly)
  defp query([], _, _, _mode), do: []

  defp query(ids, {from, to}, fulfillment, mode) do
    dimension = if mode == :daily, do: "local_day", else: "extract(isodow from local_day)::int"

    Repo.query!(
      """
      WITH local_orders AS (
        SELECT timezone(COALESCE(bi.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow'),
                 timezone('UTC',o.inserted_at)) AS local_at
        FROM orders o
        LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
        WHERE o.branch_id=ANY($1::uuid[]) AND o.deleted_at IS NULL
          AND ($4::text='all' OR o.fulfillment_type::text=$4::text)
          AND o.inserted_at >= $2::date - interval '1 day'
          AND o.inserted_at < $3::date + interval '2 days'
      ), buckets AS (
        SELECT local_at::date local_day,extract(hour from local_at)::int local_hour
        FROM local_orders WHERE local_at::date BETWEEN $2::date AND $3::date
      )
      SELECT #{dimension} bucket,local_hour,count(*)::bigint
      FROM buckets GROUP BY bucket,local_hour ORDER BY bucket,local_hour
      """,
      [Enum.map(ids, &Ecto.UUID.dump!/1), from, to, fulfillment]
    ).rows
    |> Enum.map(fn [day, hour, total] -> {day, hour, total} end)
  end
end
