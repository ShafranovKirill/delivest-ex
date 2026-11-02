defmodule Delivest.Repo.Migrations.ResetAmbiguousIntegrationHealth do
  use Ecto.Migration

  # The previous migration turned an old `warning` row into `status = ok` and
  # kept `checked_at`. A warning alone never proved a connection result, and a
  # real success followed by a warning cannot be told apart from a converted
  # row. Such results are therefore reset to unknown: the warning and its time
  # stay, `checked_at = NULL` means "connection not checked".
  #
  # Affected providers are those that write warnings: Frontpad, iiko and
  # r_keeper (menu/catalog), YooKassa (payments reconciliation) and ATOL
  # (cash register). They need one manual connection check after the upgrade.
  @legacy_warning_sql """
  UPDATE integration_health
  SET warning = COALESCE(warning, message),
      warning_at = COALESCE(warning_at, checked_at),
      status = NULL,
      message = NULL,
      checked_at = NULL
  WHERE status = 'warning'
  """

  @ambiguous_ok_sql """
  UPDATE integration_health
  SET status = NULL,
      message = NULL,
      checked_at = NULL
  WHERE status = 'ok' AND warning IS NOT NULL
  """

  def up do
    alter table(:integration_health) do
      modify :status, :string, null: true, from: {:string, null: false}
    end

    execute @legacy_warning_sql
    execute @ambiguous_ok_sql
  end

  def down do
    # The old schema cannot store an unknown result. `warning` is the closest
    # value: the previous UI showed it as unchecked without inventing success.
    execute """
    UPDATE integration_health
    SET status = COALESCE(status, 'warning')
    WHERE status IS NULL
    """

    alter table(:integration_health) do
      modify :status, :string, null: false, from: {:string, null: true}
    end
  end

  # Used by the migration regression tests to exercise the data part alone.
  def legacy_warning_sql, do: @legacy_warning_sql
  def ambiguous_ok_sql, do: @ambiguous_ok_sql
end
