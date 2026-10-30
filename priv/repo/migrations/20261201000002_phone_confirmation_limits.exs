defmodule Delivest.Repo.Migrations.PhoneConfirmationLimits do
  use Ecto.Migration

  def change do
    alter table(:phone_confirmations) do
      add :call_number, :string
    end

    create index(:phone_confirmations, [:phone, :inserted_at])
    create index(:phone_confirmations, [:session_id, :inserted_at])
  end
end
