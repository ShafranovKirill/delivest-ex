defmodule Delivest.Repo.Migrations.AddTimezones do
  use Ecto.Migration

  def change do
    alter table(:franchise_settings) do
      add :timezone, :string, null: false, default: "Europe/Moscow"
    end

    alter table(:branch_info) do
      add :timezone, :string
    end
  end
end
