defmodule Delivest.Repo.Migrations.CreateIntegrationHealth do
  use Ecto.Migration

  # The original version of this migration ran after the generated
  # `add_warning_to_integration_health` migration, so a clean database could
  # not be migrated. The version is now before that migration. Existing
  # databases already have this table under the old version, therefore both
  # operations are idempotent.
  def change do
    create_if_not_exists table(:integration_health, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :branch_id, :uuid
      add :status, :string, null: false
      add :message, :text
      add :checked_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists unique_index(:integration_health, [:provider, :branch_id],
                           nulls_distinct: false
                         )
  end
end
