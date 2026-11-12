defmodule Delivest.Repo.Migrations.PopularAutoSnapshot do
  use Ecto.Migration

  def change do
    alter table(:popular_settings) do
      add :auto_product_ids, {:array, :binary_id}, null: false, default: []
      add :calculated_at, :utc_datetime
    end
  end
end
