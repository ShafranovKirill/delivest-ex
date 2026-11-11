defmodule Delivest.Repo.Migrations.FunnelCapture do
  use Ecto.Migration

  def change do
    create table(:funnel_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :branch_id, references(:branches, type: :uuid), null: false
      add :owner_key, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :last_at, :utc_datetime_usec, null: false
    end

    create index(:funnel_sessions, [:branch_id, :owner_key, :last_at])
    create index(:funnel_sessions, [:last_at])

    create table(:funnel_events) do
      add :event_id, :uuid, null: false
      add :branch_id, references(:branches, type: :uuid), null: false
      add :owner_key, :string, null: false
      add :session_id, references(:funnel_sessions, type: :uuid), null: false
      add :event, :string, null: false
      add :source_type, :string, null: false
      add :utm_source, :string
      add :utm_medium, :string
      add :utm_campaign, :string
      add :received_at, :utc_datetime_usec, null: false
    end

    create unique_index(:funnel_events, [:branch_id, :owner_key, :event_id])
    create index(:funnel_events, [:received_at])
    create index(:funnel_events, [:session_id])
  end
end
