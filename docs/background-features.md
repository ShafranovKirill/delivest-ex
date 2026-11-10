# Optional background features

The installation is one franchise with branches. `segments` is initially disabled. Only a host operator can change availability through a release RPC; staff permissions and HTTP endpoints do not expose the setting.

```elixir
Delivest.Release.configure_feature("segments", :franchise, true, "operator-name")
Delivest.Release.configure_feature("segments", {:branch, "branch-uuid"}, true, "operator-name")
Delivest.Release.configure_feature("segments", {:branch, "branch-uuid"}, false, "operator-name")

{:ok, preview} = Delivest.Release.preview_feature_disable("segments", :franchise)
Delivest.Release.configure_feature("segments", :franchise, false, "operator-name",
  confirm_dependents: preview)
```

The franchise gate must be enabled before any branch is effective. Unknown features and branches fail closed. A repeated write of the same value is idempotent. Every actual change has a `feature_audits` row with actor and generation. Branch changes also advance the franchise generation to stop a shared calculation.

`Delivest.Features.snapshot/2` returns a generation token for an enabled scope. Calculations check `Background.still_enabled?/1` between batches. Their final database writes use `Background.publish/2` for franchise results or `Background.publish/4` with a captured branch token for branch results. Publication uses a short transaction that locks the feature gates and the current schedule row, then checks the token and job ownership before running the writes. Calculations themselves run outside this transaction.

One Oban cron entry calls `Background.Dispatcher` on the existing maintenance queue every five minutes. It reads at most ten indexed due schedule rows, coalesces missed runs, and enqueues the static allowlisted worker on the shared `background` queue (concurrency 1). Feature keys live in `Features.Registry`; optional tasks live in `Background.Registry` with their feature, scope, handler, interval, and limits. A feature may have no background task. `segments.refresh` recurs every 24 hours after a successful run. Critical queue backlog above `:background_pressure_limit` (default 50 eligible jobs) defers scheduling and execution. Long handlers call `Background.checkpoint/1` between batches to defer if pressure rises. `Background.status/0` and `Background.overdue_count/0` expose due time, last success/error, running state, and overdue work. No CPU estimate is used.

Oban retries failed calculations at most three times. Failure details are kept in Oban job errors; the schedule records a generic error marker to avoid leaking data. A terminal or missing job is recovered by the next dispatcher tick, marked with a generic failure and rescheduled for its regular interval. Disabling cancels pending jobs and deletes the schedule; an executing job exits at its next checkpoint and cannot publish. Reenabling starts a fresh due run and does not replay missed daily runs.

The dispatcher has a 30-second timeout; a calculation has a 15-minute timeout and a 30-second PostgreSQL statement timeout. The runner holds one database connection for the calculation to apply the statement limit without a long transaction, then restores that connection's previous limit. Oban terminates a timed-out worker and closes its checked-out connection. The next retry starts the calculation again.
