defmodule Delivest.Analytics.Reports.Prune do
  @moduledoc "Bounded calendar-month retention for published and abandoned analytics snapshots."
  alias Delivest.Repo

  @batch 500
  def batch_size, do: @batch

  # Report dates are branch-local calendar days; retention uses a UTC calendar-date
  # cutoff shifted by 36 months, with Date.shift's end-of-month clamping.
  def prune(now \\ Date.utc_today()) do
    oldest = Date.shift(now, month: -36)

    states =
      Repo.query!(
        """
        DELETE FROM analytics_report_states WHERE ctid IN (
          SELECT ctid FROM analytics_report_states WHERE day < $1
          ORDER BY day LIMIT $2 FOR UPDATE SKIP LOCKED
        )
        """,
        [oldest, @batch]
      ).num_rows

    snapshots =
      Repo.query!(
        """
        DELETE FROM analytics_report_snapshots WHERE id IN (
          SELECT p.id FROM analytics_report_snapshots p
          WHERE (p.day < $1 OR p.inserted_at < timezone('UTC', now()) - interval '1 day')
            AND NOT EXISTS (SELECT 1 FROM analytics_report_states s WHERE s.snapshot_id=p.id)
          ORDER BY p.day LIMIT $2 FOR UPDATE SKIP LOCKED
        )
        """,
        [oldest, @batch]
      ).num_rows

    %{states: states, snapshots: snapshots}
  end
end
