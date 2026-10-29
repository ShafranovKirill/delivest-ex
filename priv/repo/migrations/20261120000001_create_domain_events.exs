defmodule Delivest.Repo.Migrations.CreateDomainEvents do
  use Ecto.Migration

  def change do
    create table(:domain_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :type, :string, null: false
      add :aggregate_type, :string, null: false
      add :aggregate_id, :uuid, null: false
      add :branch_id, :uuid
      add :payload, :map, null: false, default: %{}
      add :actor, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:domain_events, [:aggregate_type, :aggregate_id])
    create index(:domain_events, [:branch_id, :inserted_at])
    create index(:domain_events, [:type])
  end
end
