defmodule Delivest.Repo.Migrations.AddThumbKeyToMediaFiles do
  use Ecto.Migration

  def change do
    alter table(:media_files) do
      add :thumb_key, :string
    end
  end
end
