defmodule Delivest.Repo.Migrations.MarketingPushFrequency do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :marketing_push_limit_count, :integer, null: false, default: 1
      add :marketing_push_window_hours, :integer, null: false, default: 24
    end

    create constraint(:franchise_settings, :marketing_push_limit_count_range,
             check: "marketing_push_limit_count BETWEEN 1 AND 100"
           )

    create constraint(:franchise_settings, :marketing_push_window_hours_range,
             check: "marketing_push_window_hours BETWEEN 1 AND 720"
           )

    create table(:marketing_push_reservations, primary_key: false) do
      add :intent_id,
          references(:customer_notification_intents, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :reserved_at, :utc_datetime_usec, null: false
    end

    create index(:marketing_push_reservations, [:client_id, :reserved_at])

    execute(
      """
      INSERT INTO marketing_push_reservations (intent_id, client_id, reserved_at)
      SELECT d.intent_id, n.client_id, max(d.updated_at)
      FROM customer_notification_push_deliveries AS d
      JOIN customer_notification_intents AS i ON i.id = d.intent_id
      JOIN customer_notifications AS n ON n.id = i.notification_id
      WHERE n.source_feature = 'marketing_policies'
        AND i.channel = 'push'
        AND d.status IN ('sent', 'unknown', 'inflight')
        AND d.updated_at > now() - interval '720 hours'
      GROUP BY d.intent_id, n.client_id
      """,
      "SELECT 1"
    )
  end
end
