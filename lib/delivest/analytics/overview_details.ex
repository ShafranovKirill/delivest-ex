defmodule Delivest.Analytics.OverviewDetails do
  @moduledoc "Bounded, authorized order and sales drilldowns for statistics."
  alias Delivest.{Identity, Repo}
  alias Delivest.Analytics.Overview
  alias Delivest.Identity.Branch.FulfillmentSettings
  alias Delivest.Oms.OrderSource

  @kinds [:products, :categories, :hourly, :fulfillment, :payment, :source, :destination]
  @order_kinds [:completed, :cancelled, :refunds]

  def read(staff, scope, {from, to} = period, kind) when kind in @kinds do
    with :ok <- Overview.valid_period(period),
         {:ok, branches} <- Overview.authorized_branches(staff, scope) do
      ids = Enum.map(branches, &Ecto.UUID.dump!(&1.id))
      {:ok, rows(kind, ids, from, to, branches)}
    end
  end

  def read(_, _, _, _), do: {:error, :forbidden}

  def orders(staff, scope, period, kind, opts \\ [])

  def orders(staff, scope, {from, to} = period, kind, opts) when kind in @order_kinds do
    with :ok <- Overview.valid_period(period),
         true <- Identity.can?(staff, "orders.read"),
         {:ok, branches} <- Overview.authorized_branches(staff, scope) do
      ids = Enum.map(branches, &Ecto.UUID.dump!(&1.id))
      page = opts |> Keyword.get(:page, 1) |> sane_page()
      size = opts |> Keyword.get(:limit, 50) |> sane_size()
      {total, rows} = order_rows(ids, from, to, kind, page, size)
      {:ok, %{rows: rows, page: page, pages: max(ceil(total / size), 1), total_rows: total}}
    else
      _ -> {:error, :forbidden}
    end
  end

  def orders(_, _, _, _, _), do: {:error, :forbidden}

  defp sane_page(value) when is_integer(value) and value > 0, do: min(value, 10_000)
  defp sane_page(_), do: 1
  defp sane_size(value) when is_integer(value) and value > 0, do: min(value, 50)
  defp sane_size(_), do: 50

  defp base_sql do
    """
    WITH scoped AS (
      SELECT o.*,b.name branch_name,
        (timezone(COALESCE(bi.timezone,fs.timezone,'Europe/Moscow'),timezone('UTC',o.inserted_at))) local_at
      FROM orders o JOIN branches b ON b.id=o.branch_id
      LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
      CROSS JOIN (SELECT timezone FROM franchise_settings LIMIT 1) fs
      WHERE o.branch_id=ANY($1::uuid[]) AND o.deleted_at IS NULL
        AND o.inserted_at >= ($2::date - interval '1 day')
        AND o.inserted_at < ($3::date + interval '2 days')
    ), selected AS (
      SELECT * FROM scoped WHERE local_at::date BETWEEN $2::date AND $3::date
    ), refunds AS (
      SELECT f.order_id,sum(f.amount)::bigint amount,count(*)::bigint n,string_agg(DISTINCT f.reason, '; ') reason
      FROM order_refunds f JOIN selected s ON s.id=f.order_id
      WHERE f.status='succeeded' GROUP BY f.order_id
    )
    """
  end

  defp rows(kind, ids, from, to, _branches) when kind in [:products, :categories] do
    {key, title} =
      case kind do
        :products -> {"i.product_id::text", "max(i.title)"}
        :categories -> {"i.category_id::text", "max(i.category_name)"}
      end

    Repo.query!(
      base_sql() <>
        """
        SELECT #{key},#{title},sum(i.price*i.quantity)::bigint,
          count(DISTINCT s.id)::bigint,sum(i.quantity)::bigint
        FROM selected s JOIN order_items i ON i.order_id=s.id
        WHERE s.status='completed'
        GROUP BY #{key} ORDER BY 3 DESC LIMIT 100
        """,
      [ids, from, to]
    ).rows
    |> Enum.map(fn [key, title, revenue, orders, quantity] ->
      %{
        key: key,
        title: title,
        revenue: revenue,
        orders: orders,
        quantity: quantity,
        revenue_basis: :gross_before_refunds
      }
    end)
  end

  defp rows(kind, ids, from, to, branches) do
    base_key =
      case kind do
        :hourly -> "extract(hour from s.local_at)::int"
        :fulfillment -> "s.fulfillment_type::text"
        :payment -> "s.payment_method::text"
        :source -> "COALESCE(s.source,'unknown')"
        :destination -> "COALESCE(s.crm->>'provider','own')"
      end

    allowed =
      Map.new(branches, fn branch ->
        info = branch.info

        values =
          case kind do
            :fulfillment ->
              FulfillmentSettings.enabled(info && info.fulfillment) |> Enum.map(&to_string/1)

            :source ->
              enabled =
                info && info.channels && info.channels.yandex_eda &&
                  info.channels.yandex_eda.enabled

              OrderSource.own() ++ if(enabled, do: ["yandex_eda"], else: [])

            :destination ->
              crm = info && info.crm

              ["own"] ++
                if(crm && crm.enabled && crm.provider, do: [to_string(crm.provider)], else: [])

            _ ->
              []
          end

        {branch.id, values}
      end)
      |> Jason.encode!()

    key =
      if kind in [:fulfillment, :source, :destination] do
        "CASE WHEN ($4::text::jsonb -> s.branch_id::text) ? (#{base_key}) " <>
          "THEN #{base_key} ELSE 'other' END"
      else
        base_key
      end

    Repo.query!(
      base_sql() <>
        """
        SELECT #{key},COALESCE(sum(GREATEST(s.total_amount-COALESCE(f.amount,0),0)),0)::bigint,
          count(*)::bigint
        FROM selected s LEFT JOIN refunds f ON f.order_id=s.id
        WHERE s.status='completed' GROUP BY #{key} ORDER BY 1
        """,
      if(kind in [:hourly, :payment], do: [ids, from, to], else: [ids, from, to, allowed])
    ).rows
    |> Enum.map(fn [key, revenue, orders] -> %{key: key, revenue: revenue, orders: orders} end)
  end

  defp order_rows(ids, from, to, kind, page, size) do
    condition =
      case kind do
        :completed -> "s.status='completed'"
        :cancelled -> "s.status='cancelled'"
        :refunds -> "s.status='completed' AND COALESCE(f.n,0)>0"
      end

    sql =
      base_sql() <>
        """
        SELECT s.id::text,s.number,s.branch_id::text,s.branch_name,s.status::text,
          s.total_amount,COALESCE(f.amount,0),
          CASE WHEN s.status='cancelled' THEN s.cancel_reason::text ELSE f.reason END,
          s.inserted_at,count(*) OVER ()::bigint
        FROM selected s LEFT JOIN refunds f ON f.order_id=s.id
        WHERE #{condition} ORDER BY s.inserted_at DESC,s.id DESC LIMIT $4 OFFSET $5
        """

    rows = Repo.query!(sql, [ids, from, to, size, (page - 1) * size]).rows

    total =
      case rows do
        [[_, _, _, _, _, _, _, _, _, n] | _] ->
          n

        [] when page == 1 ->
          0

        [] ->
          [[count]] =
            Repo.query!(
              base_sql() <>
                "SELECT count(*)::bigint FROM selected s LEFT JOIN refunds f ON f.order_id=s.id WHERE #{condition}",
              [ids, from, to]
            ).rows

          count
      end

    rows =
      Enum.map(rows, fn [
                          id,
                          number,
                          branch_id,
                          branch_name,
                          status,
                          amount,
                          refund,
                          reason,
                          at,
                          _
                        ] ->
        %{
          id: id,
          number: number,
          branch_id: branch_id,
          branch_name: branch_name,
          status: status,
          total_amount: amount,
          refund_amount: refund,
          reason: reason,
          inserted_at: at
        }
      end)

    {total, rows}
  end
end
