defmodule Delivest.Repo.Migrations.MarketingPolicyLifecycle do
  use Ecto.Migration

  def change do
    alter table(:marketing_policies) do
      add :deleted_at, :utc_datetime
    end

    create index(:marketing_policies, [:deleted_at, :id])
  end
end
