defmodule Delivest.Repo.Migrations.OrderNumbers do
  use Ecto.Migration

  def up do
    alter table(:branches) do
      add :code, :string
    end

    flush()

    execute("""
    UPDATE branches b SET code = c.code
    FROM (
      SELECT id,
             CASE WHEN rn = 1 THEN base ELSE left(base, 4) || rn END AS code
      FROM (
        SELECT id, base, row_number() OVER (PARTITION BY base ORDER BY inserted_at, id) AS rn
        FROM (
          SELECT id, inserted_at,
                 CASE WHEN length(s) >= 2 THEN s
                      ELSE 'BR' || row_number() OVER (ORDER BY inserted_at, id) END AS base
          FROM (
            SELECT id, inserted_at,
                   upper(left(regexp_replace(coalesce(slug, ''), '[^a-zA-Z0-9]', '', 'g'), 6)) AS s
            FROM branches
          ) raw
        ) based
      ) ranked
    ) c
    WHERE b.id = c.id
    """)

    alter table(:branches) do
      modify :code, :string, null: false
    end

    create unique_index(:branches, [:code], name: :branches_code_uk)

    create table(:order_counters, primary_key: false) do
      add :branch_id, :binary_id, primary_key: true
      add :business_date, :date, primary_key: true
      add :value, :integer, null: false
    end

    alter table(:orders) do
      add :business_date, :date
      add :daily_number, :integer
    end

    flush()

    zone = Delivest.LocalTime.timezone()

    execute("""
    UPDATE orders SET business_date =
      ((inserted_at AT TIME ZONE 'UTC') AT TIME ZONE '#{zone}' - interval '5 hours')::date
    """)

    execute("""
    UPDATE orders o SET daily_number = n.rn,
      number = to_char(o.business_date, 'YYMMDD') || '-' ||
        coalesce((SELECT code FROM branches WHERE id = o.branch_id), 'XX') || '-' ||
        lpad(n.rn::text, 3, '0')
    FROM (
      SELECT id, row_number() OVER (PARTITION BY branch_id, business_date ORDER BY inserted_at, id) AS rn
      FROM orders
    ) n
    WHERE o.id = n.id
    """)

    execute("""
    INSERT INTO order_counters (branch_id, business_date, value)
    SELECT branch_id, business_date, max(daily_number) FROM orders GROUP BY branch_id, business_date
    """)

    alter table(:orders) do
      modify :business_date, :date, null: false
      modify :daily_number, :integer, null: false
    end

    drop index(:orders, [:number])
    create unique_index(:orders, [:number])
    create unique_index(:orders, [:branch_id, :business_date, :daily_number])

    execute("DROP SEQUENCE order_number_seq")
  end

  def down do
    execute("CREATE SEQUENCE order_number_seq MINVALUE 0 MAXVALUE 25999 CYCLE START WITH 0")
    drop index(:orders, [:branch_id, :business_date, :daily_number])
    drop index(:orders, [:number])
    create index(:orders, [:number])

    alter table(:orders) do
      remove :business_date
      remove :daily_number
    end

    drop table(:order_counters)
    drop index(:branches, [:code], name: :branches_code_uk)

    alter table(:branches) do
      remove :code
    end
  end
end
