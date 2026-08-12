defmodule Delivest.Repo.Migrations.CreateRoleAndUpdateAccounts do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :permissions, :jsonb, default: "[]", null: false

      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:name], name: :roles__name__uk)

    alter table(:staff) do
      add :role_id,
          references(:roles,
            on_delete: :restrict,
            type: :binary_id,
            name: :staff__role_id__fk
          ),
          null: false
    end

    create index(:staff, [:role_id])
  end
end
