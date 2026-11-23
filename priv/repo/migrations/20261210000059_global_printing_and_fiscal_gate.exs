defmodule Delivest.Repo.Migrations.GlobalPrintingAndFiscalGate do
  use Ecto.Migration

  def up do
    alter table(:franchise_settings) do
      add :printing, :map
      add :fiscal_enabled, :boolean, default: false, null: false
    end

    # Promote only an unambiguous configuration. Distinct branch presets remain
    # in branch_info until a franchise administrator explicitly saves a global one.
    execute """
    UPDATE franchise_settings
    SET printing = (SELECT MIN(printing::text)::jsonb FROM branch_info)
    WHERE (SELECT COUNT(DISTINCT printing) FROM branch_info) = 1
    """

    # Preserve already active ATOL issuance on upgraded installations.
    execute """
    UPDATE franchise_settings
    SET fiscal_enabled = TRUE
    WHERE EXISTS (
      SELECT 1 FROM branch_info
      WHERE fiscal->>'mode' = 'own'
        AND COALESCE((fiscal->>'enabled')::boolean, TRUE)
    )
    """
  end

  def down do
    alter table(:franchise_settings) do
      remove :printing
      remove :fiscal_enabled
    end
  end
end
