defmodule Delivest.Repo.Migrations.BackgroundFeatures do
  use Ecto.Migration

  def change do
    create table(:feature_gates, primary_key: false) do
      add :feature, :string, primary_key: true
      add :scope_key, :string, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :generation, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create table(:feature_audits) do
      add :feature, :string, null: false
      add :scope_key, :string, null: false
      add :enabled, :boolean, null: false
      add :generation, :bigint, null: false
      add :actor, :string, null: false
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:feature_audits, [:feature, :scope_key, :inserted_at])

    create table(:background_schedules) do
      add :kind, :string, null: false
      add :scope_key, :string, null: false
      add :next_at, :utc_datetime_usec, null: false
      add :last_success_at, :utc_datetime_usec
      add :last_error_at, :utc_datetime_usec
      add :last_error, :text
      add :running, :boolean, null: false, default: false
      add :current_job_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:background_schedules, [:kind, :scope_key])
    create index(:background_schedules, [:next_at], where: "running = false")

    execute "INSERT INTO feature_gates (feature, scope_key, enabled, generation, inserted_at, updated_at) VALUES ('segments', 'franchise', false, 0, now(), now())",
            "DELETE FROM feature_gates WHERE feature = 'segments' AND scope_key = 'franchise'"
  end
end
