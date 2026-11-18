defmodule Delivest.Repo.Migrations.MoveYandexAdsCredentialsToSettings do
  use Ecto.Migration

  def change do
    alter table(:yandex_ads_settings) do
      add :direct_token_plain, :text
      add :metrika_token_plain, :text
      add :refresh_token_plain, :text
      add :measurement_token_plain, :text
      add :oauth_client_id, :text
      add :oauth_client_secret, :text
    end
  end
end
