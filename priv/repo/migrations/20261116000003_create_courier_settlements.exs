defmodule Delivest.Repo.Migrations.CreateCourierSettlements do
  use Ecto.Migration

  def change do
    create table(:courier_settlements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :courier_id, references(:staff, type: :binary_id, on_delete: :delete_all), null: false
      add :accepted_by_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :cash_amount, :integer, null: false
      add :card_amount, :integer, null: false
      add :orders_count, :integer, null: false
      add :until, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:courier_settlements, [:branch_id, :courier_id, :until])

    create index(:deliveries, [:courier_id, :branch_id, :closed_at],
             where: "status = 'delivered'"
           )
  end
end
