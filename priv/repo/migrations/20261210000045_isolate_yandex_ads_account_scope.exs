defmodule Delivest.Repo.Migrations.IsolateYandexAdsAccountScope do
  use Ecto.Migration

  def up do
    alter table(:yandex_ads_settings) do
      add :account_scope, :text
    end

    execute "UPDATE yandex_ads_settings SET account_scope=md5(random()::text || clock_timestamp()::text)"

    execute "UPDATE yandex_ads_costs c SET account=s.account_scope FROM yandex_ads_settings s WHERE c.account=COALESCE(s.client_login,'direct-owner')"
  end

  def down do
    execute "UPDATE yandex_ads_costs c SET account=COALESCE(s.client_login,'direct-owner') FROM yandex_ads_settings s WHERE c.account=s.account_scope"

    alter table(:yandex_ads_settings) do
      remove :account_scope
    end
  end
end
