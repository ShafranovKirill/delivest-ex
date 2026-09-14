defmodule Delivest.Repo.Migrations.CreateOrderNumberSequence do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE order_number_seq MINVALUE 0 MAXVALUE 25999 CYCLE START WITH 0;"
  end

  def down do
    execute "DROP SEQUENCE order_number_seq;"

    alter table(:orders) do
      modify :number, :integer
    end
  end
end
