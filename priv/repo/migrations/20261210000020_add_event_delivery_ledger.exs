defmodule Delivest.Repo.Migrations.AddEventDeliveryLedger do
  use Ecto.Migration

  def change do
    alter table(:domain_events) do
      add :sequence, :bigint
    end

    execute """
    WITH numbered AS (
      SELECT id, row_number() OVER
        (PARTITION BY aggregate_type, aggregate_id ORDER BY inserted_at, id) AS seq
      FROM domain_events
    )
    UPDATE domain_events e SET sequence = numbered.seq
    FROM numbered WHERE e.id = numbered.id
    """

    execute "ALTER TABLE domain_events ALTER COLUMN sequence SET NOT NULL",
            "ALTER TABLE domain_events ALTER COLUMN sequence DROP NOT NULL"

    create unique_index(:domain_events, [:aggregate_type, :aggregate_id, :sequence])
    create constraint(:domain_events, :domain_events_sequence_positive, check: "sequence > 0")

    create table(:event_sequences, primary_key: false) do
      add :aggregate_type, :string, null: false
      add :aggregate_id, :uuid, null: false
      add :value, :bigint, null: false
    end

    create unique_index(:event_sequences, [:aggregate_type, :aggregate_id])

    execute """
    INSERT INTO event_sequences (aggregate_type, aggregate_id, value)
    SELECT aggregate_type, aggregate_id, max(sequence)
    FROM domain_events GROUP BY aggregate_type, aggregate_id
    """

    create table(:event_deliveries, primary_key: false) do
      add :event_id, references(:domain_events, type: :uuid, on_delete: :delete_all), null: false
      add :subscriber, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :delivered_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_deliveries, [:event_id, :subscriber])
    create index(:event_deliveries, [:subscriber, :status])

    create constraint(:event_deliveries, :event_deliveries_status_valid,
             check: "status IN ('pending', 'delivered', 'resolved')"
           )

    execute """
    WITH jobs AS (
    SELECT (args->>'event_id')::uuid AS event_id, args->>'subscriber' AS subscriber,
    bool_or(state = 'completed') AS completed
    FROM oban_jobs
    WHERE worker = 'Delivest.Events.DeliverWorker'
    AND args ? 'event_id' AND args ? 'subscriber'
    GROUP BY 1, 2
    )
    INSERT INTO event_deliveries (event_id, subscriber, status, delivered_at, inserted_at, updated_at)
    SELECT j.event_id, j.subscriber,
    CASE WHEN j.completed THEN 'delivered' ELSE 'pending' END,
    CASE WHEN j.completed THEN now() ELSE NULL END,
    now(), now()
    FROM jobs j JOIN domain_events e ON e.id = j.event_id
    """
  end
end
