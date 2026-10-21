defmodule Delivest.Repo.Migrations.CreateIdentity do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :permissions, :jsonb, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:name], name: :roles__name__uk)

    create table(:staff, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login, :string, null: false
      add :password_hash, :string, null: false
      add :name, :string

      add :role_id,
          references(:roles, type: :binary_id, on_delete: :restrict, name: :staff__role_id__fk),
          null: false

      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:staff, [:login], name: :staff__login__uk)
    create index(:staff, [:role_id])

    create table(:branches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :is_active, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:branches, [:name], name: :branches__name__uk)
    create unique_index(:branches, [:slug], name: :branches__slug_uk)

    create table(:staff_branches, primary_key: false) do
      add :staff_id,
          references(:staff,
            type: :binary_id,
            on_delete: :delete_all,
            name: :staff_branches__staff_id__fk
          ),
          primary_key: true

      add :branch_id,
          references(:branches,
            type: :binary_id,
            on_delete: :delete_all,
            name: :staff_branches__branch_id__fk
          ),
          primary_key: true

      timestamps()
    end

    create index(:staff_branches, [:branch_id])

    create unique_index(:staff_branches, [:staff_id, :branch_id],
             name: :staff_branches__staff_id_branch_id__uk
           )

    create table(:branch_info, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :branch_id,
          references(:branches,
            type: :binary_id,
            on_delete: :restrict,
            name: :branch_info__branch_id__fk
          ),
          null: false

      add :address, :string
      add :phone_number, :string
      add :delivery_time, :integer
      add :working_hours, :map, default: %{}
      add :vk_url, :string
      add :whatsapp_url, :string
      add :instagram_url, :string
      add :crm, :map, null: false, default: %{}
      add :ycart_settings, :map, default: %{enabled: false}

      timestamps()
    end

    create index(:branch_info, [:branch_id])

    execute(
      "CREATE TYPE client_status AS ENUM ('active', 'blocked')",
      "DROP TYPE client_status"
    )

    create table(:clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phone, :string, null: false
      add :name, :string
      add :status, :client_status, null: false, default: "active"
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clients, [:phone],
             where: "deleted_at IS NULL",
             name: :clients__phone__uk
           )

    create index(:clients, [:status], name: :clients__status__idx)

    create table(:client_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :city, :string
      add :street, :string, null: false
      add :house, :string
      add :apartment, :string
      add :floor, :string
      add :entrance, :string
      add :intercom, :string

      timestamps(type: :utc_datetime)
    end

    create index(:client_addresses, [:client_id, :updated_at])

    create table(:phone_confirmations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phone, :string, null: false
      add :session_id, :string, null: false
      add :call_id, :string, null: false
      add :confirmed_at, :utc_datetime
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:phone_confirmations, [:call_id])
  end
end
