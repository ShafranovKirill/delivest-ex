defmodule Delivest.Repo.Migrations.AddYandexDelivery do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :yandex_delivery, :map
    end

    create table(:yandex_delivery_journals, primary_key: false) do
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :cursor, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:deliveries, [:provider, :external_id], where: "external_id IS NOT NULL")
  end
end
