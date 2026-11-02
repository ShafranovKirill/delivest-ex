defmodule Delivest.Repo.Migrations.AddWarningToIntegrationHealth do
  use Ecto.Migration

  def up do
    alter table(:integration_health) do
      add :warning, :text
      add :warning_at, :utc_datetime_usec
      modify :checked_at, :utc_datetime_usec, null: true, from: {:utc_datetime_usec, null: false}
    end

    execute """
    UPDATE integration_health
    SET warning = message, warning_at = checked_at, status = 'ok', message = NULL
    WHERE status = 'warning'
    """
  end

  def down do
    execute """
    UPDATE integration_health
    SET status = 'warning', message = warning, warning_at = NULL
    WHERE warning IS NOT NULL
    """

    execute """
    UPDATE integration_health
    SET checked_at = COALESCE(checked_at, warning_at, NOW())
    WHERE checked_at IS NULL
    """

    alter table(:integration_health) do
      remove :warning
      remove :warning_at
      modify :checked_at, :utc_datetime_usec, null: false, from: {:utc_datetime_usec, null: true}
    end
  end
end
