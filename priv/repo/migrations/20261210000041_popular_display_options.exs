defmodule Delivest.Repo.Migrations.PopularDisplayOptions do
  use Ecto.Migration

  def change do
    alter table(:popular_settings) do
      add :show_in_menu, :boolean, null: false, default: false
      add :show_in_cart, :boolean, null: false, default: true
    end
  end
end
