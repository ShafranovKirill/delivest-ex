defmodule Delivest.Repo.Migrations.AddCrmCommandLedger do
  use Ecto.Migration

  def change do
    create table(:crm_commands, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :order_id, references(:orders, type: :uuid), null: false
      add :provider, :string, null: false
      add :action, :string, null: false
      add :args, :map, null: false, default: %{}
      add :event_id, references(:domain_events, type: :uuid)
      add :job_id, :bigint
      add :status, :string, null: false, default: "pending"
      add :claim_token, :uuid
      add :claim_attempt, :integer
      add :claimed_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :last_error, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crm_commands, [:event_id, :action], where: "event_id IS NOT NULL")
    create unique_index(:crm_commands, [:job_id], where: "job_id IS NOT NULL")
    create index(:crm_commands, [:order_id, :provider, :id])

    create constraint(:crm_commands, :crm_commands_status,
             check: "status IN ('pending','running','succeeded','unknown','failed','resolved')"
           )

    execute """
            INSERT INTO crm_commands (order_id, provider, action, args, job_id, status, inserted_at, updated_at)
            SELECT o.id, COALESCE(o.crm->>'provider', 'unknown'), j.args->>'action', j.args, j.id,
              CASE
                WHEN j.state = 'completed' THEN 'succeeded'
                WHEN j.state IN ('available', 'scheduled', 'retryable') THEN 'pending'
                ELSE 'unknown'
              END,
              j.inserted_at, j.inserted_at
            FROM oban_jobs j JOIN orders o ON o.id = (j.args->>'order_id')::uuid
            WHERE j.worker = 'Delivest.Integrations.Crm.CommandWorker'
              AND j.args ? 'order_id' AND j.args ? 'action'
            ORDER BY j.id
            """,
            "DELETE FROM crm_commands WHERE job_id IS NOT NULL"
  end
end
