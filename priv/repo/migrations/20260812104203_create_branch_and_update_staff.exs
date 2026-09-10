defmodule Delivest.Repo.Migrations.CreateBranchAndUpdateStaff do
  use Ecto.Migration

  def change do
    create table(:branches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :is_active, :boolean, default: false, null: false

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:branches, [:name], name: :branches__name__uk)
    create unique_index(:branches, [:slug], name: :branches__slug_uk)

    create table(:staff_branches, primary_key: false) do
      add :staff_id,
          references(:staff,
            on_delete: :delete_all,
            type: :binary_id,
            name: :staff_branches__staff_id__fk
          ),
          primary_key: true

      add :branch_id,
          references(:branches,
            on_delete: :delete_all,
            type: :binary_id,
            name: :staff_branches__branch_id__fk
          ),
          primary_key: true

      timestamps()
    end

    create index(:staff_branches, [:staff_id])
    create index(:staff_branches, [:branch_id])

    create unique_index(:staff_branches, [:staff_id, :branch_id],
             name: :staff_branches__staff_id_branch_id__uk
           )
  end
end
