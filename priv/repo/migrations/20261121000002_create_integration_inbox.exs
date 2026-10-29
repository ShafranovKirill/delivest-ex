defmodule Delivest.Repo.Migrations.CreateIntegrationInbox do
  use Ecto.Migration

  def change do
    create table(:integration_inbox, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :event_id, :string, null: false
      add :branch_id, :uuid
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :processed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:integration_inbox, [:provider, :event_id])
    create index(:integration_inbox, [:status, :inserted_at])
  end
end
