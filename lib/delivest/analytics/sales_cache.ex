defmodule Delivest.Analytics.SalesCache do
  @moduledoc "Daily base-sales rollups. Missing or dirty history is always read from source."
  require Logger
  alias Delivest.{Analytics, LocalTime, Repo}
  alias Delivest.Analytics.SalesCacheWorker

  @batch 12

  def read(scope, {from, to} = period, metric, opts, fallback) do
    ids = List.wrap(scope) |> Enum.uniq() |> Enum.sort()
    days = Date.diff(to, from) + 1

    if ids == [] or days < 1 or days > 366 do
      fallback.()
    else
      case payloads(ids, period) do
        {:ok, rows} -> merge(rows, metric, opts, period)
        :missing -> fallback.()
      end
    end
  rescue
    error in DBConnection.ConnectionError ->
      Logger.warning(
        "Sales rollup unavailable; using source queries: #{Exception.message(error)}"
      )

      fallback.()

    error in Postgrex.Error ->
      if error.postgres &&
           error.postgres.code in [:undefined_table, :query_canceled, :lock_not_available] do
        Logger.warning(
          "Sales rollup unavailable; using source queries: #{Exception.message(error)}"
        )

        fallback.()
      else
        reraise error, __STACKTRACE__
      end
  end

  defp zones(ids) do
    Repo.query!(
      """
      SELECT b.id::text,COALESCE(i.timezone,(SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow')
      FROM unnest($1::uuid[]) b(id) LEFT JOIN branch_info i ON i.branch_id=b.id
      """,
      [Enum.map(ids, &Ecto.UUID.dump!/1)]
    ).rows
  end

  defp payloads(ids, {from, to} = period) do
    zones = zones(ids)

    rows =
      Repo.query!(
        """
        SELECT branch_id::text,day,timezone,revision,dirty,payload FROM sales_daily_rollups
        WHERE branch_id=ANY($1::uuid[]) AND day BETWEEN $2 AND $3 ORDER BY branch_id,day
        """,
        [Enum.map(ids, &Ecto.UUID.dump!/1), from, to]
      ).rows

    cached =
      Map.new(rows, fn [id, day, zone, revision, dirty, payload] ->
        {{id, day}, {zone, revision, dirty, payload}}
      end)

    needed =
      for [id, zone] <- zones,
          day <- Date.range(from, to),
          Date.before?(day, LocalTime.today(zone)),
          do: {id, day, zone}

    complete? =
      Enum.all?(needed, fn {id, day, zone} ->
        case cached[{id, day}] do
          {^zone, _revision, false, payload} when is_map(payload) -> true
          _ -> false
        end
      end)

    cond do
      not complete? ->
        queue_missing(zones, period)
        :missing

      Enum.any?(zones, fn [_id, zone] -> Date.after?(to, LocalTime.today(zone)) end) ->
        :missing

      true ->
        signature =
          {ids, period,
           rows |> Enum.map(fn [id, day, zone, rev, dirty, _] -> {id, day, zone, rev, dirty} end),
           zones}

        now = System.monotonic_time(:millisecond)
        # All methods rendering one screen share one fresh recent-day calculation.
        screens =
          Process.get({__MODULE__, :screen}, [])
          |> Enum.filter(fn {_, at, _} -> now - at < 1_000 end)

        case Enum.find(screens, fn {key, _, _} -> key == signature end) do
          {^signature, _at, payloads} ->
            {:ok, payloads}

          _ ->
            historical =
              Enum.map(needed, fn {id, day, _zone} ->
                {_, _, _, payload} = cached[{id, day}]
                {day, payload}
              end)

            current =
              for [id, zone] <- zones,
                  today = LocalTime.today(zone),
                  not Date.before?(to, today),
                  not Date.after?(from, today) do
                Cachex.del(:branch_cache, {:timezone, id})
                {today, encode(Analytics.sales_day_payload(id, today))}
              end

            payloads = historical ++ current

            Process.put(
              {__MODULE__, :screen},
              Enum.take([{signature, System.monotonic_time(:millisecond), payloads} | screens], 3)
            )

            {:ok, payloads}
        end
    end
  end

  defp queue_missing(zones, {from, to}) do
    Enum.each(zones, fn [id, zone] ->
      last = Enum.min_by([to, Date.add(LocalTime.today(zone), -1)], &Date.to_gregorian_days/1)

      if not Date.after?(from, last) do
        Repo.query!(
          """
          INSERT INTO sales_daily_rollups(branch_id,day)
          SELECT $1::uuid,d::date FROM generate_series($2::date,$3::date,interval '1 day') d
          ON CONFLICT DO NOTHING
          """,
          [Ecto.UUID.dump!(id), from, last]
        )
      end
    end)

    %{} |> SalesCacheWorker.new() |> Oban.insert()
    :ok
  end

  def rebuild_batch do
    candidates =
      Repo.query!(
        """
        SELECT r.branch_id::text,r.day FROM sales_daily_rollups r
        LEFT JOIN branch_info i ON i.branch_id=r.branch_id
        WHERE r.dirty AND r.day < (now() AT TIME ZONE COALESCE(i.timezone,
          (SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow'))::date
        ORDER BY r.day DESC,r.branch_id LIMIT $1
        """,
        [@batch]
      ).rows

    Enum.each(candidates, fn [id, day] ->
      case rebuild_day(id, day) do
        {:ok, _} -> :ok
        {:error, reason} -> raise "Sales rollup failed: #{inspect(reason)}"
      end
    end)

    length(candidates)
  end

  def rebuild_day(id, day) do
    # No source/cache-row lock during calculation. Every source mutation bumps
    # revision in its own transaction; publication below succeeds only if that
    # revision is unchanged. A racing commit either rejects this publication or
    # dirties the just-published row after its short UPDATE lock is released.
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL lock_timeout='2s'")
      Repo.query!("SET LOCAL statement_timeout='20s'")

      [[locked]] =
        Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))", [
          "sales:#{id}:#{day}"
        ]).rows

      if locked do
        case Repo.query!(
               "SELECT revision FROM sales_daily_rollups WHERE branch_id=$1::uuid AND day=$2 AND dirty",
               [Ecto.UUID.dump!(id), day]
             ).rows do
          [[revision]] ->
            [[^id, zone]] = zones([id])

            if Date.before?(day, LocalTime.today(zone)) do
              Cachex.del(:branch_cache, {:timezone, id})
              payload = encode(Analytics.sales_day_payload(id, day))

              Repo.query!(
                """
                UPDATE sales_daily_rollups SET payload=$3,timezone=$4,dirty=false,computed_at=timezone('UTC',now())
                WHERE branch_id=$1::uuid AND day=$2 AND revision=$5
                """,
                [Ecto.UUID.dump!(id), day, payload, zone, revision]
              )
            end

          _ ->
            :ok
        end
      end
    end)
  end

  defp encode(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp merge(rows, :summary, _opts, _period) do
    total =
      sum_maps(
        Enum.map(rows, fn {_, p} -> p["summary"] end),
        ~w(revenue orders_count items_sold cancelled_count lost_count)
      )

    total
    |> Map.put(
      :avg_check,
      if(total.orders_count > 0, do: round(total.revenue / total.orders_count), else: 0)
    )
  end

  defp merge(rows, :crm_split, _opts, _period) do
    total = sum_maps(Enum.map(rows, fn {_, p} -> p["crm_split"] end), ~w(crm_orders crm_revenue))
    count = Enum.sum(Enum.map(rows, fn {_, p} -> p["confirmation"]["count"] end))

    sum =
      Enum.reduce(rows, Decimal.new(0), fn {_, p}, acc ->
        Decimal.add(acc, Decimal.new(p["confirmation"]["sum"]))
      end)

    Map.put(
      total,
      :avg_confirm_seconds,
      if(count > 0,
        do: sum |> Decimal.div(count) |> Decimal.round() |> Decimal.to_integer(),
        else: nil
      )
    )
  end

  defp merge(rows, :daily, _opts, {from, to}) do
    totals =
      Enum.reduce(rows, %{}, fn {day, p}, acc ->
        Map.update(acc, day, p["summary"], fn r ->
          %{
            "revenue" => r["revenue"] + p["summary"]["revenue"],
            "orders_count" => r["orders_count"] + p["summary"]["orders_count"]
          }
        end)
      end)

    for day <- Date.range(from, to),
        row = Map.get(totals, day, %{}),
        do: %{date: day, revenue: row["revenue"] || 0, orders: row["orders_count"] || 0}
  end

  defp merge(rows, :status_counts, _opts, _period) do
    Enum.reduce(rows, %{}, fn {_, p}, acc ->
      Enum.reduce(p["status_counts"], acc, fn {key, value}, acc ->
        Map.update(acc, String.to_existing_atom(key), value, &(&1 + value))
      end)
    end)
  end

  defp merge(rows, :hourly, _opts, _period) do
    groups = grouped(rows, "hourly", "hour", ~w(revenue orders))
    for hour <- 0..23, do: Map.get(groups, hour, %{hour: hour, revenue: 0, orders: 0})
  end

  defp merge(rows, :top_products, opts, _period) do
    sort =
      if Keyword.get(opts, :sort_by) == :quantity,
        do: [:quantity, :revenue],
        else: [:revenue, :quantity]

    result =
      grouped(rows, "top_products", "product_id", ~w(quantity revenue orders))
      |> Map.values()
      |> Enum.sort_by(fn row -> Enum.map(sort, &(-Map.fetch!(row, &1))) end)

    result =
      if Keyword.get(opts, :limit, 20) == :all,
        do: result,
        else: Enum.take(result, Keyword.get(opts, :limit, 20))

    share(result, :revenue)
  end

  defp merge(rows, :categories, _opts, _period) do
    grouped(rows, "categories", "category_id", ~w(quantity revenue orders))
    |> Map.values()
    |> Enum.map(fn r ->
      r |> Map.put(:products, length(Enum.uniq(r.product_ids))) |> Map.delete(:product_ids)
    end)
    |> Enum.sort_by(&(-&1.revenue))
    |> share(:revenue)
  end

  defp merge(rows, metric, _opts, _period) when metric in [:fulfillment_type, :payment_method] do
    grouped(rows, Atom.to_string(metric), "key", ~w(orders revenue))
    |> Map.values()
    |> Enum.map(
      &Map.update!(&1, :key, fn key -> if key, do: String.to_existing_atom(key), else: nil end)
    )
    |> Enum.sort_by(&(-&1.orders))
    |> share(:orders)
  end

  defp sum_maps(rows, keys),
    do:
      Map.new(keys, fn key ->
        {String.to_existing_atom(key), Enum.sum(Enum.map(rows, &Map.get(&1, key, 0)))}
      end)

  defp grouped(rows, metric, key, fields) do
    rows
    |> Enum.flat_map(fn {_, p} -> p[metric] end)
    |> Enum.reduce(%{}, fn row, acc ->
      row =
        Map.drop(row, ["share"])
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)

      id = Map.fetch!(row, String.to_existing_atom(key))

      Map.update(acc, id, row, fn old ->
        merged =
          Enum.reduce(fields, old, fn field, acc ->
            field = String.to_existing_atom(field)
            Map.update!(acc, field, &(&1 + Map.fetch!(row, field)))
          end)

        Enum.reduce([:title, :category_name, :product_ids], merged, fn field, acc ->
          cond do
            field == :product_ids and Map.has_key?(row, field) ->
              Map.put(acc, field, Enum.uniq(Map.get(acc, field, []) ++ row[field]))

            Map.has_key?(row, field) ->
              Map.put(acc, field, Enum.max([Map.get(acc, field), row[field]]))

            true ->
              acc
          end
        end)
      end)
    end)
  end

  defp share(rows, key) do
    total = Enum.sum(Enum.map(rows, &Map.fetch!(&1, key)))

    Enum.map(
      rows,
      &Map.put(
        &1,
        :share,
        if(total > 0, do: Float.round(Map.fetch!(&1, key) * 100 / total, 1), else: 0.0)
      )
    )
  end
end
