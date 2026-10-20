defmodule Delivest.Repo.Migrations.AddSessionIdToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :session_id, :string
    end

    create index(:orders, [:session_id, :inserted_at])
  end
end
