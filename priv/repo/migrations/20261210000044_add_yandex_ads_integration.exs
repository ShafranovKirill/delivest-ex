defmodule Delivest.Repo.Migrations.AddYandexAdsIntegration do
  use Ecto.Migration

  def change do
    create table(:yandex_ads_settings, primary_key: false) do
      add :id, :integer, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :privacy_approved, :boolean, null: false, default: false
      add :browser_enabled, :boolean, null: false, default: false
      add :conversions_enabled, :boolean, null: false, default: false
      add :ecommerce_enabled, :boolean, null: false, default: false
      add :feed_enabled, :boolean, null: false, default: false
      add :costs_enabled, :boolean, null: false, default: false
      add :branch_ids, {:array, :uuid}, null: false, default: []
      add :counter_id, :text
      add :goal, :text, null: false, default: "delivest_order_completed"
      add :client_login, :text
      add :currency, :text, null: false, default: "RUB"
      add :timezone, :text, null: false, default: "Europe/Moscow"
      add :include_vat, :boolean, null: false, default: true
      add :direct_token, :binary
      add :metrika_token, :binary
      add :refresh_token, :binary
      add :measurement_token, :binary
      add :generation, :bigint, null: false, default: 1
      add :costs_refreshed_at, :utc_datetime_usec
      add :costs_from, :date
      add :costs_to, :date
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:yandex_ads_settings, :yandex_ads_singleton, check: "id = 1")

    create table(:yandex_ads_identities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :branch_id, references(:branches, type: :uuid, on_delete: :delete_all), null: false
      add :owner_key, :text, null: false
      add :claimed_client_id, :uuid
      add :generation, :bigint, null: false
      add :client_id, :text
      add :yclid, :text
      add :campaign_id, :text
      add :ad_id, :text
      add :captured_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:yandex_ads_identities, [:branch_id, :owner_key, :generation])
    create index(:yandex_ads_identities, [:updated_at])

    create table(:yandex_ads_order_receipts, primary_key: false) do
      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), primary_key: true
      add :branch_id, :uuid, null: false
      add :generation, :bigint, null: false
      add :counter_id, :text, null: false
      add :client_id, :text
      add :yclid, :text
      add :campaign_id, :text
      add :ad_id, :text
      add :landing_branch_id, :uuid
      add :captured_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:yandex_ads_order_receipts, [:inserted_at])

    create table(:yandex_ads_conversions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), null: false
      add :branch_id, :uuid, null: false
      add :generation, :bigint, null: false
      add :counter_id, :text, null: false
      add :channel, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :reason, :text
      add :amount, :bigint, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :payload, :map, null: false, default: %{}
      add :upload_id, :text
      add :provider_status, :text
      add :attempted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:yandex_ads_conversions, [:order_id, :counter_id, :channel])
    create index(:yandex_ads_conversions, [:status, :updated_at])

    create table(:yandex_ads_costs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :generation, :bigint, null: false
      add :account, :text, null: false
      add :day, :date, null: false
      add :campaign_id, :text, null: false
      add :campaign_name, :text, null: false
      add :cost_micros, :bigint, null: false
      add :impressions, :bigint, null: false
      add :clicks, :bigint, null: false
      add :currency, :text, null: false
      add :include_vat, :boolean, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:yandex_ads_costs, [:generation, :account, :day, :campaign_id])
    create index(:yandex_ads_costs, [:day])
  end
end
