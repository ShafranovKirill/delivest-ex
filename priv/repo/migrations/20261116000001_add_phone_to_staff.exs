defmodule Delivest.Repo.Migrations.AddPhoneToStaff do
  use Ecto.Migration

  def change do
    alter table(:staff) do
      add :phone, :string
    end
  end
end
