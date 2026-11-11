defmodule Delivest.Repo.Migrations.CreateProductOperationMappings do
  use Ecto.Migration

  def change do
    create table(:product_operation_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_key, :string, null: false

      add :target_branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :entity_type, :string, null: false
      add :target_entity_id, :binary_id, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :product_operation_mappings,
             [:source_key, :target_branch_id, :entity_type],
             name: :product_operation_mapping_source_index
           )

    create unique_index(
             :product_operation_mappings,
             [:target_branch_id, :entity_type, :target_entity_id],
             name: :product_operation_mapping_target_index
           )
  end
end
