defmodule Delivest.Repo.Migrations.AddTagsToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :tags, {:array, :string}, null: false, default: []
    end
  end
end
