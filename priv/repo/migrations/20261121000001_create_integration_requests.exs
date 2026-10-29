defmodule Delivest.Repo.Migrations.CreateIntegrationRequests do
  use Ecto.Migration

  def change do
    create table(:integration_requests, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :branch_id, :uuid
      add :order_id, :uuid
      add :direction, :string, null: false
      add :method, :string, null: false
      add :url, :text, null: false
      add :status, :integer
      add :duration_ms, :integer
      add :request, :text
      add :response, :text
      add :error, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:integration_requests, [:provider, :branch_id, :inserted_at])
    create index(:integration_requests, [:order_id])
    create index(:integration_requests, [:inserted_at])
  end
end
