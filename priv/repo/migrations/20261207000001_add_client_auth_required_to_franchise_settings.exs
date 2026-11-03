defmodule Delivest.Repo.Migrations.AddClientAuthRequiredToFranchiseSettings do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :client_auth_required, :boolean, null: false, default: false
    end
  end
end
