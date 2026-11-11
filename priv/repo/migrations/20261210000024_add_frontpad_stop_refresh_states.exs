defmodule Delivest.Repo.Migrations.AddFrontpadStopRefreshStates do
  use Ecto.Migration

  def change do
    create table(:frontpad_stop_refresh_states, primary_key: false) do
      add :branch_id, references(:branches, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :job_id, :bigint
      add :status, :string, null: false, default: "queued"
      add :last_attempt_at, :utc_datetime_usec
      add :last_success_at, :utc_datetime_usec
      add :last_good_count, :integer
      add :last_good_unlinked, {:array, :string}, default: []
      add :last_error, :string
      timestamps(type: :utc_datetime_usec)
    end
  end
end
