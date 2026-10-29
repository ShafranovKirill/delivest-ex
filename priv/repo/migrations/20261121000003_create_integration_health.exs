defmodule Delivest.Repo.Migrations.CreateIntegrationHealth do
  use Ecto.Migration

  def change do
    create table(:integration_health, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :branch_id, :uuid
      add :status, :string, null: false
      add :message, :text
      add :checked_at, :utc_datetime_usec, null: false
    end

    create unique_index(:integration_health, [:provider, :branch_id], nulls_distinct: false)
  end
end
