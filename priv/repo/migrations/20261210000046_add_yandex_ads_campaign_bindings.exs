defmodule Delivest.Repo.Migrations.AddYandexAdsCampaignBindings do
  use Ecto.Migration

  def change do
    create table(:yandex_ads_campaign_bindings, primary_key: false) do
      add :account_scope, :text, primary_key: true

      add :advertising_link_id,
          references(:advertising_links, type: :uuid, on_delete: :delete_all), primary_key: true

      add :campaign_id, :text, null: false
      add :bound_by_id, references(:staff, type: :uuid, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:yandex_ads_campaign_bindings, [:account_scope, :campaign_id])

    create constraint(:yandex_ads_campaign_bindings, :yandex_campaign_numeric_id,
             check: "campaign_id ~ '^[1-9][0-9]{0,29}$'"
           )
  end
end
