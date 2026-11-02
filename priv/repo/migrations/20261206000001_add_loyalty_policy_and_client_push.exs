defmodule Delivest.Repo.Migrations.AddLoyaltyPolicyAndClientPush do
  use Ecto.Migration

  def up do
    alter table(:franchise_settings) do
      add :loyalty_per_rubles, :integer, null: false, default: 100
      add :loyalty_stars, :integer, null: false, default: 5
      add :loyalty_expire_days, :integer, null: false, default: 180
    end

    execute("""
    INSERT INTO franchise_settings
      (id, name, primary_color, timezone,
       loyalty_per_rubles, loyalty_stars, loyalty_expire_days,
       inserted_at, updated_at)
    SELECT
      gen_random_uuid(), 'Delivest', '#48010c', 'Europe/Moscow',
      COALESCE(
        (SELECT (loyalty->>'per_rubles')::integer
         FROM branch_info
         WHERE loyalty->>'per_rubles' IS NOT NULL
         ORDER BY inserted_at
         LIMIT 1),
        100
      ),
      COALESCE(
        (SELECT (loyalty->>'stars')::integer
         FROM branch_info
         WHERE loyalty->>'stars' IS NOT NULL
         ORDER BY inserted_at
         LIMIT 1),
        5
      ),
      COALESCE(
        (SELECT (loyalty->>'expire_days')::integer
         FROM branch_info
         WHERE loyalty->>'expire_days' IS NOT NULL
         ORDER BY inserted_at
         LIMIT 1),
        180
      ),
      now(), now()
    WHERE NOT EXISTS (SELECT 1 FROM franchise_settings)
    """)

    execute("""
    UPDATE franchise_settings
    SET loyalty_per_rubles = COALESCE(
          (SELECT (loyalty->>'per_rubles')::integer
           FROM branch_info
           WHERE loyalty->>'per_rubles' IS NOT NULL
           ORDER BY inserted_at
           LIMIT 1),
          loyalty_per_rubles
        ),
        loyalty_stars = COALESCE(
          (SELECT (loyalty->>'stars')::integer
           FROM branch_info
           WHERE loyalty->>'stars' IS NOT NULL
           ORDER BY inserted_at
           LIMIT 1),
          loyalty_stars
        ),
        loyalty_expire_days = COALESCE(
          (SELECT (loyalty->>'expire_days')::integer
           FROM branch_info
           WHERE loyalty->>'expire_days' IS NOT NULL
           ORDER BY inserted_at
           LIMIT 1),
          loyalty_expire_days
        )
    """)

    create table(:client_push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :locale, :string, default: "ru"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:client_push_subscriptions, [:client_id, :endpoint])

    create table(:loyalty_expiry_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :expires_on, :date, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:loyalty_expiry_notifications, [:client_id, :expires_on])

    create index(:loyalty_entries, [:expires_at],
             where: "remaining > 0",
             name: :loyalty_entries_expiring_index
           )
  end

  def down do
    drop index(:loyalty_entries, [:expires_at], name: :loyalty_entries_expiring_index)

    drop table(:loyalty_expiry_notifications)
    drop table(:client_push_subscriptions)

    alter table(:franchise_settings) do
      remove :loyalty_per_rubles
      remove :loyalty_stars
      remove :loyalty_expire_days
    end
  end
end
