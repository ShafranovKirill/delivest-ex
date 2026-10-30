defmodule Delivest.Repo.Migrations.AddPhotoKeyToModifiers do
  use Ecto.Migration

  def change do
    alter table(:modifiers) do
      add :photo_key, :string
    end
  end
end
