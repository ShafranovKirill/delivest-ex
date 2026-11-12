defmodule Delivest.Repo.Migrations.DeliveryShowCity do
  use Ecto.Migration

  def change do
    alter table(:delivery_settings) do
      add :show_city, :boolean, null: false, default: false
      add :address_mode_set, :boolean, null: false, default: false
    end
  end
end
