defmodule Delivest.Repo.Migrations.CreateYookassaSettings do
  use Ecto.Migration

  def change do
    create table(:yookassa_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shop_id, :string
      add :secret_key, :string
      add :webhook_token, :string

      timestamps(type: :utc_datetime)
    end
  end
end
