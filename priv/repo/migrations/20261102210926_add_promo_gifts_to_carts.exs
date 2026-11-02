defmodule Delivest.Repo.Migrations.AddPromoGiftsToCarts do
  use Ecto.Migration

  def change do
    alter table(:carts) do
      add :promo_gifts, :map, null: false, default: %{}
    end
  end
end
