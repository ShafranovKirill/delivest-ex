defmodule Delivest.Repo.Migrations.AddMediaVariantKeys do
  use Ecto.Migration

  def change do
    alter table(:media_files) do
      add(:variant_keys, :map, default: %{}, null: false)
    end
  end
end
