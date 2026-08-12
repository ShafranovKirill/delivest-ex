defmodule Delivest.Repo.Migrations.CreateBranchAndUpdateAccounts do
  use Ecto.Migration

  def change do
    create table(:branches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:branches, [:name], name: :branches__name__uk)

    alter table(:staff) do
      add :branch_id,
          references(:branches,
            on_delete: :restrict,
            type: :binary_id,
            name: :staff__branch_id__fk
          )
    end

    create index(:staff, [:branch_id])
  end
end
