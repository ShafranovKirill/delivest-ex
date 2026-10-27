defmodule Delivest.Repo.Migrations.CreateYandexEdaSettings do
  use Ecto.Migration

  def change do
    create table(:yandex_eda_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, :string
      add :client_secret, :string
      add :partner_name, :string
      add :push_client_id, :string
      add :push_client_secret, :string

      timestamps(type: :utc_datetime)
    end
  end
end
