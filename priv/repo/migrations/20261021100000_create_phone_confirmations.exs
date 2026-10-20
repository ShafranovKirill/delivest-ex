defmodule Delivest.Repo.Migrations.CreatePhoneConfirmations do
  use Ecto.Migration

  def change do
    create table(:phone_confirmations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phone, :string, null: false
      add :session_id, :string, null: false
      add :call_id, :string, null: false
      add :confirmed_at, :utc_datetime
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:phone_confirmations, [:call_id])
  end
end
