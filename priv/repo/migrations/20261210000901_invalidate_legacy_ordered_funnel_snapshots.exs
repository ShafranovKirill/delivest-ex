defmodule Delivest.Repo.Migrations.InvalidateLegacyOrderedFunnelSnapshots do
  use Ecto.Migration

  def up do
    # Only reconstructible cohorts are dirtied. Expired raw events must never
    # silently turn an old unordered snapshot into a versioned ordered one.
    execute """
    UPDATE analytics_report_states s
    SET revision=s.revision+1, updated_at=timezone('UTC',now())
    WHERE s.feature='analytics_funnel' AND s.snapshot_id IS NOT NULL
      AND s.day >= ((now() AT TIME ZONE COALESCE(
        (SELECT timezone FROM branch_info WHERE branch_id=s.branch_id),
        (SELECT timezone FROM franchise_settings LIMIT 1), 'Europe/Moscow'))::date - 89)
      AND NOT EXISTS (
        SELECT 1 FROM analytics_report_rows r
        WHERE r.snapshot_id=s.snapshot_id AND r.dimension='stage'
          AND r.key='session_started' AND r.counts->>'algorithm_version'='2'
      )
    """
  end

  def down, do: :ok
end
