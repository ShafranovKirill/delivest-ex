defmodule Delivest.Repo.Migrations.CreateChannelProducts do
  use Ecto.Migration

  def change do
    create table(:channel_products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel, :string, null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, null: false, default: true
      add :price, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_products, [:channel, :product_id])
  end
end
