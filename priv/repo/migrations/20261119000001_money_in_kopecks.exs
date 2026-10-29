defmodule Delivest.Repo.Migrations.MoneyInKopecks do
  use Ecto.Migration

  @columns [
    products: [:price],
    channel_products: [:price],
    order_items: [:price, :base_price],
    orders: [:total_amount, :subtotal_amount, :discount_amount, :delivery_amount],
    promo_redemptions: [:discount],
    courier_settlements: [:cash_amount, :card_amount]
  ]

  def up do
    for {table, columns} <- @columns, column <- columns do
      execute("ALTER TABLE #{table} ALTER COLUMN #{column} TYPE bigint USING #{column} * 100")
    end

    execute("""
    ALTER TABLE products ALTER COLUMN old_price TYPE bigint USING
      CASE WHEN replace(old_price, ',', '.') ~ '^\\s*\\d+(\\.\\d{1,2})?\\s*$'
           THEN round(trim(replace(old_price, ',', '.'))::numeric * 100)::bigint
      END
    """)

    for table <- [:delivery_settings, :delivery_zones], do: scale_thresholds(table, "* 100")

    execute("""
    UPDATE orders SET promotions = (
      SELECT coalesce(jsonb_agg(p || jsonb_build_object('discount', (p->>'discount')::bigint * 100) ORDER BY n), '[]'::jsonb)
      FROM jsonb_array_elements(promotions) WITH ORDINALITY AS e(p, n)
    )
    WHERE jsonb_array_length(promotions) > 0
    """)

    execute("""
    UPDATE orders
    SET channel = jsonb_set(channel, '{details,delivery_fee}',
      to_jsonb(round((channel->'details'->>'delivery_fee')::numeric * 100)::bigint))
    WHERE jsonb_typeof(channel->'details'->'delivery_fee') = 'number'
    """)

    execute("""
    UPDATE crm_catalog_snapshots SET products = (
      SELECT coalesce(jsonb_agg(CASE WHEN jsonb_typeof(p->'price') = 'number'
                  THEN p || jsonb_build_object('price', round((p->>'price')::numeric * 100)::bigint)
                  ELSE p END ORDER BY n), '[]'::jsonb)
      FROM jsonb_array_elements(products) WITH ORDINALITY AS e(p, n)
    )
    WHERE jsonb_typeof(products) = 'array'
    """)
  end

  def down do
    for {table, columns} <- @columns, column <- columns do
      execute("ALTER TABLE #{table} ALTER COLUMN #{column} TYPE integer USING #{column} / 100")
    end

    execute("""
    ALTER TABLE products ALTER COLUMN old_price TYPE varchar(255) USING
      CASE WHEN old_price IS NOT NULL THEN (old_price / 100)::text END
    """)

    for table <- [:delivery_settings, :delivery_zones], do: scale_thresholds(table, "/ 100")

    execute("""
    UPDATE orders SET promotions = (
      SELECT coalesce(jsonb_agg(p || jsonb_build_object('discount', (p->>'discount')::bigint / 100) ORDER BY n), '[]'::jsonb)
      FROM jsonb_array_elements(promotions) WITH ORDINALITY AS e(p, n)
    )
    WHERE jsonb_array_length(promotions) > 0
    """)

    execute("""
    UPDATE orders
    SET channel = jsonb_set(channel, '{details,delivery_fee}',
      to_jsonb((channel->'details'->>'delivery_fee')::bigint / 100))
    WHERE jsonb_typeof(channel->'details'->'delivery_fee') = 'number'
    """)

    execute("""
    UPDATE crm_catalog_snapshots SET products = (
      SELECT coalesce(jsonb_agg(CASE WHEN jsonb_typeof(p->'price') = 'number'
                  THEN p || jsonb_build_object('price', (p->>'price')::bigint / 100)
                  ELSE p END ORDER BY n), '[]'::jsonb)
      FROM jsonb_array_elements(products) WITH ORDINALITY AS e(p, n)
    )
    WHERE jsonb_typeof(products) = 'array'
    """)
  end

  defp scale_thresholds(table, op) do
    execute("""
    UPDATE #{table} SET thresholds = (
      SELECT coalesce(jsonb_agg(t || jsonb_build_object(
        'order_from', (t->>'order_from')::bigint #{op},
        'price', (t->>'price')::bigint #{op}
      ) ORDER BY n), '[]'::jsonb)
      FROM jsonb_array_elements(thresholds) WITH ORDINALITY AS e(t, n)
    )
    WHERE jsonb_array_length(thresholds) > 0
    """)
  end
end
