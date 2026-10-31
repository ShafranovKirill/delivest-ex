defmodule Delivest.Repo.Migrations.AddOperatorNoteToClients do
  use Ecto.Migration

  def change do
    alter table(:clients) do
      add :operator_note, :text
    end
  end
end
