defmodule Delivest.Repo.Migrations.AddEventDeliveries do
  use Ecto.Migration

  def up do
    create table(:event_deliveries, primary_key: false) do
      add :event_id, references(:domain_events, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :subscriber, :string, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_deliveries, [:subscriber, :status, :event_id])

    execute """
    INSERT INTO event_deliveries (event_id, subscriber, status, last_error, inserted_at, updated_at)
    SELECT CASE WHEN j.args->>'event_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           THEN (j.args->>'event_id')::uuid END, j.args->>'subscriber',
      CASE WHEN bool_or(j.state = 'completed') THEN 'delivered'
           WHEN bool_or(j.attempt > 0) THEN 'blocked'
           WHEN bool_or(j.state IN ('available', 'scheduled', 'retryable', 'executing')) THEN 'pending'
           ELSE 'blocked' END,
      CASE WHEN bool_or(j.state = 'completed') THEN NULL
           WHEN bool_or(j.attempt > 0) THEN 'Legacy attempted delivery needs verification'
           ELSE NULL END,
      min(j.inserted_at), now()
    FROM oban_jobs j
    JOIN domain_events e ON e.id = CASE
      WHEN j.args->>'event_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (j.args->>'event_id')::uuid END
    WHERE j.worker = 'Delivest.Events.DeliverWorker'
      AND j.args->>'event_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      AND j.args->>'subscriber' IN ('couriers', 'kitchen', 'push', 'crm', 'fiscal', 'payments', 'loyalty')
    GROUP BY j.args->>'event_id', j.args->>'subscriber'
    """
  end

  def down do
    drop table(:event_deliveries)
  end
end
