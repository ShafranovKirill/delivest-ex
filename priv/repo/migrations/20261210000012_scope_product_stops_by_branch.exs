defmodule Delivest.Repo.Migrations.ScopeProductStopsByBranch do
  use Ecto.Migration

  def up do
    create unique_index(:product_stops, [:branch_id, :product_id, :source],
             name: :product_stops_branch_product_source_index
           )

    drop_if_exists index(:product_stops, [:product_id, :source],
                     name: :product_stops_product_id_source_index
                   )
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM product_stops GROUP BY product_id, source HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'Cannot roll back branch-scoped stops: cross-branch product/source conflicts exist';
      END IF;
    END $$;
    """

    create unique_index(:product_stops, [:product_id, :source],
             name: :product_stops_product_id_source_index
           )

    drop_if_exists index(:product_stops, [:branch_id, :product_id, :source],
                     name: :product_stops_branch_product_source_index
                   )
  end
end
