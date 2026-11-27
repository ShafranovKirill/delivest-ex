defmodule Delivest.Repo.Migrations.AddSavedPaymentMethods do
  use Ecto.Migration

  def change do
    alter table(:yookassa_settings) do
      add :saved_payment_methods_enabled, :boolean, null: false, default: false
    end

    create table(:saved_payment_methods, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :client_id, references(:clients, type: :uuid, on_delete: :delete_all), null: false
      add :shop_id, :string, null: false
      add :provider_method_id, :string, null: false
      add :type, :string
      add :title, :string
      add :last4, :string
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_payment_methods, [:client_id, :shop_id, :provider_method_id],
             name: :saved_payment_methods_owner_shop_provider_index
           )

    create index(:saved_payment_methods, [:client_id, :shop_id], where: "deleted_at IS NULL")
  end
end
