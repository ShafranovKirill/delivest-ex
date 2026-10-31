defmodule Delivest.Repo.Migrations.AddDevSkipCallsToZvonokSettings do
  use Ecto.Migration

  def change do
    alter table(:zvonok_settings) do
      add :dev_skip_calls, :boolean, null: false, default: true
    end
  end
end
