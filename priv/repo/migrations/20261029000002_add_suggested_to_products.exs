defmodule Delivest.Repo.Migrations.AddSuggestedToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :suggested, :boolean, null: false, default: false
    end
  end
end
