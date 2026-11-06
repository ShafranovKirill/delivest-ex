defmodule Delivest.Repo.Migrations.AddDomainEventSequence do
  use Ecto.Migration

  def up do
    alter table(:domain_events) do
      add :sequence, :bigint
    end

    execute "CREATE SEQUENCE domain_events_sequence_seq"

    execute """
    WITH job_order AS (
      SELECT CASE WHEN args->>'event_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             THEN (args->>'event_id')::uuid END AS event_id, min(id) AS first_job_id
      FROM oban_jobs
      WHERE worker = 'Delivest.Events.DeliverWorker'
      GROUP BY 1
    ), ranked AS (
      SELECT e.id, row_number() OVER (
        ORDER BY CASE WHEN j.first_job_id IS NULL THEN 0 ELSE 1 END,
                 j.first_job_id NULLS FIRST, e.inserted_at, e.id
      ) AS seq
      FROM domain_events e LEFT JOIN job_order j ON j.event_id = e.id
    )
    UPDATE domain_events e SET sequence = ranked.seq FROM ranked WHERE e.id = ranked.id
    """

    execute "ALTER TABLE domain_events ALTER COLUMN sequence SET DEFAULT nextval('domain_events_sequence_seq')"

    execute "SELECT setval('domain_events_sequence_seq', GREATEST(COALESCE((SELECT max(sequence) FROM domain_events), 0), 1), (SELECT count(*) > 0 FROM domain_events))"

    execute "ALTER TABLE domain_events ALTER COLUMN sequence SET NOT NULL"
    execute "ALTER SEQUENCE domain_events_sequence_seq OWNED BY domain_events.sequence"

    create unique_index(:domain_events, [:sequence])
    create index(:domain_events, [:aggregate_type, :aggregate_id, :sequence])
  end

  def down do
    drop index(:domain_events, [:aggregate_type, :aggregate_id, :sequence])
    drop unique_index(:domain_events, [:sequence])

    alter table(:domain_events) do
      remove :sequence
    end
  end
end
