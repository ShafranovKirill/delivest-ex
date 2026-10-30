defmodule Delivest.Repo.Migrations.CartItemsTimestampsUsec do
  use Ecto.Migration

  def up do
    alter table(:cart_items) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end
  end

  def down do
    alter table(:cart_items) do
      modify :inserted_at, :utc_datetime, from: :utc_datetime_usec
      modify :updated_at, :utc_datetime, from: :utc_datetime_usec
    end
  end
end
