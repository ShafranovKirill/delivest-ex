defmodule Delivest.Repo.Migrations.AddNormalizedClientAddresses do
  use Ecto.Migration

  def change do
    alter table(:client_addresses) do
      add :label, :string
      add :formatted, :string
      add :fias_id, :string
      add :postal_code, :string
      add :district, :string
      add :geo_precision, :smallint
    end

    create index(:client_addresses, [:fias_id])
  end
end
