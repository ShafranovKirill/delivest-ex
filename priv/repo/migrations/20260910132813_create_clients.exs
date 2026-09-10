defmodule Delivest.Repo.Migrations.CreateClients do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE client_status AS ENUM ('guest', 'active', 'blocked')",
      "DROP TYPE client_status"
    )

    create table(:clients, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :phone, :string, null: false
      add :name, :string
      add :status, :client_status, null: false, default: "guest"

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(
             :clients,
             [:phone],
             unique: true,
             where: "deleted_at IS NULL",
             name: :clients__phone__uk
           )

    create index(:clients, [:status], name: :clients__status__idx)
  end
end
