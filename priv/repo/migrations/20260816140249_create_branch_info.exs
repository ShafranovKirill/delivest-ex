defmodule Delivest.Repo.Migrations.CreateBranchInfo do
  use Ecto.Migration

  def change do
    create table(:branch_info, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :address, :string
      add :phone_number, :string
      add :vk_url, :string
      add :whatsapp_url, :string
      add :instagram_url, :string

      add :branch_id,
          references(:branches,
            on_delete: :restrict,
            type: :binary_id,
            name: :branch_info__branch_id__fk
          ),
          null: false

      timestamps()
    end

    create index(:branch_info, [:branch_id])
  end
end
