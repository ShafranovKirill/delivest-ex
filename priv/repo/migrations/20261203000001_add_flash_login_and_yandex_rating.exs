defmodule Delivest.Repo.Migrations.AddFlashLoginAndYandexRating do
  use Ecto.Migration

  def change do
    alter table(:zvonok_settings) do
      add :login_call_mode, :string, null: false, default: "inbound"
    end

    alter table(:phone_confirmations) do
      add :mode, :string, null: false, default: "inbound"
      add :code, :string
      add :attempts, :integer, null: false, default: 0
    end

    alter table(:franchise_settings) do
      add :yandex_org_id, :string
      add :yandex_api_key, :string
    end

    create table(:franchise_ratings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :rating, :float, null: false
      add :reviews_count, :integer, null: false, default: 0
      add :fetched_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:franchise_ratings, [:provider])
  end
end
