defmodule Delivest.Repo.Migrations.AddOrderToProducts do
  use Ecto.Migration

  def up do
    alter table(:products) do
      add :order, :float
    end

    execute """
    UPDATE products AS p
    SET "order" = ranked.position
    FROM (
      SELECT id, row_number() OVER (PARTITION BY category_id ORDER BY lower(name), inserted_at) AS position
      FROM products
    ) AS ranked
    WHERE p.id = ranked.id
    """
  end

  def down do
    alter table(:products) do
      remove :order
    end
  end
end
