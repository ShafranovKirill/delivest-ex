defmodule Delivest.Repo.Migrations.CreateStaffPushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:staff_push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :staff_id, references(:staff, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:staff_push_subscriptions, [:endpoint])
    create index(:staff_push_subscriptions, [:staff_id])
  end
end
