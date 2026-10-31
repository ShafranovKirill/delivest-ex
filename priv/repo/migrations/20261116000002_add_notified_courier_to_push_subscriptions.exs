defmodule Delivest.Repo.Migrations.AddNotifiedCourierToPushSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:push_subscriptions) do
      add :notified_courier, :string
    end
  end
end
