defmodule Delivest.Repo.Migrations.CreatePushTables do
  use Ecto.Migration

  def change do
    create table(:push_keys) do
      add :public_key, :string, null: false
      add :private_key, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :locale, :string
      add :notified_status, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:order_id, :endpoint])
  end
end
