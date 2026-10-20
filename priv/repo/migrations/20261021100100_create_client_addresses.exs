defmodule Delivest.Repo.Migrations.CreateClientAddresses do
  use Ecto.Migration

  def change do
    create table(:client_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :city, :string
      add :street, :string, null: false
      add :house, :string
      add :apartment, :string
      add :floor, :string
      add :entrance, :string
      add :intercom, :string

      timestamps(type: :utc_datetime)
    end

    create index(:client_addresses, [:client_id, :updated_at])
  end
end
