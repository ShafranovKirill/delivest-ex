defmodule Delivest.Repo.Migrations.CreateZvonokSettings do
  use Ecto.Migration

  def change do
    create table(:zvonok_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :public_key, :string
      add :campaign_id, :string
      add :webhook_token, :string

      timestamps(type: :utc_datetime)
    end
  end
end
