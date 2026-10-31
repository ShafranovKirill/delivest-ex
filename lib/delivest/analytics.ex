defmodule Delivest.Analytics do
  import Ecto.Query

  alias Delivest.LocalTime
  alias Delivest.Oms.{Order, OrderItem, OrderScopes}
  alias Delivest.Repo

  @type period :: {Date.t(), Date.t()}

  @presets ~w(today yesterday week month this_month custom)

  def presets, do: @presets

  @spec resolve_period(String.t() | nil, String.t() | nil, String.t() | nil, binary() | nil) ::
          period()
  def resolve_period(preset, from \\ nil, to \\ nil, branch_id \\ nil) do
    today = LocalTime.today(LocalTime.timezone(branch_id))

    case preset do
      "today" ->
        {today, today}

      "yesterday" ->
        {Date.add(today, -1), Date.add(today, -1)}

      "month" ->
        {Date.add(today, -29), today}

      "this_month" ->
        {Date.beginning_of_month(today), today}

      "custom" ->
        with {:ok, f} <- parse_date(from), {:ok, t} <- parse_date(to) do
          if Date.compare(f, t) == :gt, do: {t, f}, else: {f, t}
        else
          _ -> {Date.add(today, -6), today}
        end

      _week_or_unknown ->
        {Date.add(today, -6), today}
    end
  end

  @spec previous_period(period()) :: period()
  def previous_period({from, to}) do
    days = Date.diff(to, from) + 1
    {Date.add(from, -days), Date.add(from, -1)}
  end

  @spec summary(binary(), period()) :: map()
  def summary(branch_id, period) do
    totals = branch_id |> period_orders(period) |> select(^period_totals()) |> Repo.one()

    items_sold =
      branch_id
      |> items_query(period)
      |> select([_o, i], coalesce(sum(i.quantity), 0))
      |> Repo.one()

    %{revenue: revenue, orders_count: orders_count} = totals
    revenue = to_int(revenue)

    %{
      revenue: revenue,
      orders_count: orders_count,
      avg_check: if(orders_count > 0, do: round(revenue / orders_count), else: 0),
      items_sold: to_int(items_sold),
      cancelled_count: totals.cancelled_count,
      lost_count: totals.lost_count
    }
  end

  @spec crm_split(binary(), period()) :: map()
  def crm_split(branch_id, period) do
    result = branch_id |> sales_orders(period) |> select(^crm_totals()) |> Repo.one()

    %{
      crm_orders: result.crm_orders,
      crm_revenue: to_int(result.crm_revenue),
      avg_confirm_seconds: result.avg_confirm_seconds && to_int(result.avg_confirm_seconds)
    }
  end

  @spec daily(binary(), period()) :: [%{date: Date.t(), revenue: integer(), orders: integer()}]
  def daily(branch_id, {from, to} = period) do
    tz = LocalTime.timezone(branch_id)

    rows =
      branch_id
      |> sales_orders(period)
      |> group_by([o], selected_as(:day))
      |> select([o], %{
        day:
          selected_as(
            fragment("(timezone(?, timezone('UTC', ?)))::date", ^tz, o.inserted_at),
            :day
          ),
        revenue: coalesce(sum(o.total_amount), 0),
        orders: count(o.id)
      })
      |> Repo.all()
      |> Map.new(&{&1.day, &1})

    for date <- Date.range(from, to) do
      row = Map.get(rows, date, %{revenue: 0, orders: 0})
      %{date: date, revenue: to_int(row.revenue), orders: row.orders}
    end
  end

  @spec hourly(binary(), period()) :: [%{hour: 0..23, revenue: integer(), orders: integer()}]
  def hourly(branch_id, period) do
    tz = LocalTime.timezone(branch_id)

    rows =
      branch_id
      |> sales_orders(period)
      |> group_by([o], selected_as(:hour))
      |> select([o], %{
        hour:
          selected_as(
            fragment(
              "extract(hour from timezone(?, timezone('UTC', ?)))::int",
              ^tz,
              o.inserted_at
            ),
            :hour
          ),
        revenue: coalesce(sum(o.total_amount), 0),
        orders: count(o.id)
      })
      |> Repo.all()
      |> Map.new(&{&1.hour, &1})

    for hour <- 0..23 do
      row = Map.get(rows, hour, %{revenue: 0, orders: 0})
      %{hour: hour, revenue: to_int(row.revenue), orders: row.orders}
    end
  end

  @spec top_products(binary(), period(), keyword()) :: [map()]
  def top_products(branch_id, period, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    branch_id
    |> items_query(period)
    |> group_by([_o, i], i.product_id)
    |> select([o, i], %{
      product_id: i.product_id,
      title: max(i.title),
      category_name: max(i.category_name),
      quantity: sum(i.quantity),
      revenue: sum(i.price * i.quantity),
      orders: count(o.id, :distinct)
    })
    |> sort_products(Keyword.get(opts, :sort_by, :revenue))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_amounts/1)
    |> with_share(:revenue)
  end

  @spec categories(binary(), period()) :: [map()]
  def categories(branch_id, period) do
    branch_id
    |> items_query(period)
    |> group_by([_o, i], i.category_id)
    |> select([o, i], %{
      category_id: i.category_id,
      category_name: max(i.category_name),
      quantity: sum(i.quantity),
      revenue: selected_as(sum(i.price * i.quantity), :revenue),
      orders: count(o.id, :distinct),
      products: count(i.product_id, :distinct)
    })
    |> order_by(desc: selected_as(:revenue))
    |> Repo.all()
    |> Enum.map(&normalize_amounts/1)
    |> with_share(:revenue)
  end

  @spec breakdown(binary(), period(), :fulfillment_type | :payment_method) :: [map()]
  def breakdown(branch_id, period, field) when field in [:fulfillment_type, :payment_method] do
    branch_id
    |> sales_orders(period)
    |> group_by([o], field(o, ^field))
    |> select([o], %{
      key: field(o, ^field),
      orders: count(o.id),
      revenue: coalesce(sum(o.total_amount), 0)
    })
    |> order_by([o], desc: count(o.id))
    |> Repo.all()
    |> Enum.map(&normalize_amounts/1)
    |> with_share(:orders)
  end

  @spec status_counts(binary(), period()) :: %{atom() => non_neg_integer()}
  def status_counts(branch_id, period) do
    branch_id
    |> period_orders(period)
    |> group_by([o], o.status)
    |> select([o], {o.status, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @spec client_summary(binary(), [binary()] | :all) :: map()
  def client_summary(client_id, branch_ids) do
    base =
      Order
      |> where([o], o.client_id == ^client_id and is_nil(o.deleted_at))
      |> OrderScopes.sold()
      |> scope_branches(branch_ids)

    totals =
      base
      |> select([o], %{
        orders_count: count(o.id),
        spent: coalesce(sum(o.total_amount), 0),
        first_order_at: min(o.inserted_at),
        last_order_at: max(o.inserted_at)
      })
      |> Repo.one()

    favourites =
      base
      |> join(:inner, [o], i in OrderItem, on: i.order_id == o.id)
      |> group_by([_o, i], i.product_id)
      |> select([_o, i], %{title: max(i.title), quantity: selected_as(sum(i.quantity), :qty)})
      |> order_by(desc: selected_as(:qty))
      |> limit(5)
      |> Repo.all()
      |> Enum.map(&%{&1 | quantity: to_int(&1.quantity)})

    spent = to_int(totals.spent)

    totals
    |> Map.put(:spent, spent)
    |> Map.put(
      :avg_check,
      if(totals.orders_count > 0, do: round(spent / totals.orders_count), else: 0)
    )
    |> Map.put(:favourites, favourites)
  end

  defp period_orders(branch_id, {from, to}) do
    from(o in Order,
      where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
      where: o.inserted_at >= ^LocalTime.start_of_day_utc(from, LocalTime.timezone(branch_id)),
      where: o.inserted_at <= ^LocalTime.end_of_day_utc(to, LocalTime.timezone(branch_id))
    )
  end

  defp sales_orders(branch_id, period) do
    branch_id
    |> period_orders(period)
    |> OrderScopes.sold()
  end

  defp crm_totals do
    crm = dynamic([o], not is_nil(o.crm))

    confirmed =
      dynamic(
        [o],
        fragment("?->>'status'", o.crm) == "sent" and not is_nil(fragment("?->>'sent_at'", o.crm))
      )

    %{
      crm_orders: dynamic([o], filter(count(o.id), ^crm)),
      crm_revenue: dynamic([o], coalesce(filter(sum(o.total_amount), ^crm), 0)),
      avg_confirm_seconds:
        dynamic(
          [o],
          filter(
            avg(
              fragment(
                "extract(epoch from ((?->>'sent_at')::timestamptz - ?))",
                o.crm,
                o.inserted_at
              )
            ),
            ^confirmed
          )
        )
    }
  end

  defp period_totals do
    sold = OrderScopes.sold()

    %{
      revenue: dynamic([o], coalesce(filter(sum(o.total_amount), ^sold), 0)),
      orders_count: dynamic([o], filter(count(o.id), ^sold)),
      cancelled_count: dynamic([o], filter(count(o.id), ^OrderScopes.cancelled())),
      lost_count: dynamic([o], filter(count(o.id), ^OrderScopes.lost()))
    }
  end

  defp items_query(branch_id, period) do
    branch_id
    |> sales_orders(period)
    |> join(:inner, [o], i in OrderItem, on: i.order_id == o.id)
  end

  defp scope_branches(query, :all), do: query
  defp scope_branches(query, branch_ids), do: where(query, [o], o.branch_id in ^branch_ids)

  defp sort_products(query, :quantity),
    do: order_by(query, [_o, i], desc: sum(i.quantity), desc: sum(i.price * i.quantity))

  defp sort_products(query, _revenue),
    do: order_by(query, [_o, i], desc: sum(i.price * i.quantity), desc: sum(i.quantity))

  defp normalize_amounts(row) do
    row
    |> Map.update(:revenue, 0, &to_int/1)
    |> Map.update(:quantity, 0, &to_int/1)
  end

  defp with_share(rows, key) do
    total = rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

    Enum.map(rows, fn row ->
      share = if total > 0, do: Float.round(Map.fetch!(row, key) * 100 / total, 1), else: 0.0
      Map.put(row, :share, share)
    end)
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = value), do: Decimal.to_integer(Decimal.round(value))
  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: round(value)

  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_), do: :error
end
