defmodule Delivest.Repo.Migrations.AddDailyRuns do
  use Ecto.Migration

  def change do
    create table(:daily_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :task_key, :string, null: false
      add :scope_type, :string, null: false
      add :scope_id, :string, null: false
      add :local_date, :date, null: false
      add :job_id, :bigint
      add :status, :string, null: false, default: "scheduled"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:daily_runs, [:task_key, :scope_type, :scope_id, :local_date])
    create index(:daily_runs, [:status, :updated_at])
    create index(:daily_runs, [:job_id])
  end
end
