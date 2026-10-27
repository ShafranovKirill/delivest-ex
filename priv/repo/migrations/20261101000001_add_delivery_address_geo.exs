defmodule Delivest.Repo.Migrations.AddDeliveryAddressGeo do
  use Ecto.Migration

  def change do
    create table(:dadata_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_key, :string
      add :enabled, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    alter table(:branch_info) do
      add :city, :string
    end

    alter table(:client_addresses) do
      add :latitude, :float
      add :longitude, :float
      add :comment, :string
    end
  end
end
