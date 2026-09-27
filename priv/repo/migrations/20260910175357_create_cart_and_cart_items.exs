defmodule Delivest.Repo.Migrations.CreateCartAndCartItems do
  use Ecto.Migration

  def change do
    create table(:carts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string
      add :staff_id, :binary_id
      add :branch_id, :binary_id
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:carts, [:session_id], where: "session_id IS NOT NULL")
    create index(:carts, [:staff_id], where: "staff_id IS NOT NULL")
    create index(:carts, [:branch_id])

    create table(:cart_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart_id, references(:carts, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, :binary_id, null: false
      add :quantity, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:cart_items, [:cart_id])
    create unique_index(:cart_items, [:cart_id, :product_id])
  end
end
