defmodule Delivest.Repo.Migrations.CreateLogsAndIntegrations do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :actor_type, :string, null: false
      add :actor_id, :binary_id
      add :actor_name, :string
      add :subject_type, :string, null: false
      add :subject_id, :string
      add :subject_label, :string
      add :branch_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:inserted_at])
    create index(:audit_events, [:subject_type, :inserted_at])
    create index(:audit_events, [:branch_id, :inserted_at])
    create index(:audit_events, [:actor_id, :inserted_at])
    create index(:audit_events, [:action, :inserted_at])

    create table(:app_logs) do
      add :level, :string, null: false
      add :message, :text, null: false
      add :source, :string
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:app_logs, [:inserted_at])
    create index(:app_logs, [:level, :inserted_at])

    create table(:crm_catalog_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :products, :map, null: false, default: fragment("'[]'::jsonb")
      add :issues, :map, null: false, default: fragment("'[]'::jsonb")
      add :checked_at, :utc_datetime, null: false
    end

    create unique_index(:crm_catalog_snapshots, [:branch_id])
  end
end
