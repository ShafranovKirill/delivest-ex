defmodule Delivest.Repo.Migrations.AddCancelReasonToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :cancel_reason, :string
      add :cancel_note, :string
    end
  end
end
