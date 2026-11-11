# F04 browser QA

The browser checks use a disposable PostgreSQL container named
`delivest-f04qa-pg-20261111`, bound only to `127.0.0.1:55437`. Test partitions
use `delivest_testf04qa*` and `delivest_testf04_smoke_*`; browser databases use
`delivest_e2e_f04*`. None is
the developer, demo, or production database. These databases and their
container are disposable after the final checks.

## Covered paths

- Staff creates an advertising link, copies it with browser Clipboard API, and
  sees a localized status. A denied Clipboard API reports failure; the readonly
  URL remains selectable for manual copying.
- Browser interception aborts all `/client/analytics/**` requests while a guest
  completes ordinary pickup checkout. The confirmation survives a reload, with
  one order heading and no page errors. This checks that optional analytics
  request failures do not block the core cash order.
- A real browser follows the redirect, receives a signed analytics guest cookie,
  confirms a synthetic phone using the dev-only seeded fixture, checks out, and
  completes the pickup order through staff OMS screens. Reloading the order page
  preserves its identity and the operator sees exactly one order card.
- Staff refreshes and reads the new source, funnel, and channel reports, then
  reads the franchise branch comparison. The source row retains the link's
  click, first-source client, created-order, and completed-order counts. Russian
  light and dark screenshots are attached to the browser test result; desktop
  and mobile widths are checked for settled horizontal overflow and page errors.
- Order receipt tests cover online awaiting-payment creation, independent feature
  gates, phone-resolved guest identity without a verified first-source claim,
  seven-day and same-second boundaries, future clicks, and idempotent replay.
- Funnel receipt selection uses the last event at or before the order cutoff.
  The regression confirms a later event can advance mutable session `last_at`
  without hiding the prior session or changing the captured source and timestamp.
  Migration 33 indexes `(session_id, received_at, id)` for the bounded event
  lookup. The existing session `(branch_id, owner_key, last_at)` index narrows
  candidate sessions using only the lower cutoff bound.
- Feature publication race tests use supervised tasks and remove the unboxed
  feature gate and audit data after task termination.

## Local isolation

The upstream agent integration test hardcodes the `delivest-postgres` container
name. For this QA run a temporary, untracked PATH wrapper substituted only that
name with `delivest-f04qa-pg-20261111`. The test created and dropped its unique
`policy_target_*` and `policy_stage_*` fixture databases inside the disposable
container. No existing PostgreSQL container or database was changed.

The server worktree reused the root server's installed `assets/node_modules`
through an untracked symlink so its development watcher could build JS and CSS.
The symlink is removed after checks and is not part of the patch.

## Check results

- `node --experimental-default-type=module --test assets/js/hooks/copy_link.test.mjs`:
  2 passed.
- `MIX_ENV=test TEST_DB_HOST=127.0.0.1 TEST_DB_PORT=55437
  MIX_TEST_PARTITION=f04qa mix test test/delivest/features_test.exs
  test/delivest/analytics/order_receipts_test.exs
  test/delivest_web/live/staff/advertising_live/index_test.exs`:
  16 passed before the additional boundary test.
- Repeat of `test/delivest/analytics/order_receipts_test.exs` after the boundary
  test: 7 passed.
- `mix test test/delivest/analytics/order_receipts_test.exs` after the mutable
  session cutoff regression and migration 33: 8 passed.
- Fresh test database partition `f04qa2` migrated the final migration 33 and
  passed the focused receipts, features, and advertising LiveView tests:
  18 passed. PostgreSQL listed the new composite event index.
- `PATH=/tmp/delivest-f04qa-bin:$PATH MIX_ENV=test
  DELIVEST_POLICY_INTEGRATION=1 mix test` in `agent/`: 99 passed, no skips.
- `pnpm typecheck` in `e2e/`: passed.
- `pnpm test tests/advertising-analytics.spec.ts` in `e2e/` with
  `DELIVEST_E2E_SERVER_DIR` pointing at this worktree and the disposable database:
  2 passed. Browser setup clears proxy variables for localhost and uses the
  loopback server health URL.
- Full baseline `CI=1 pnpm test` in `e2e/` with the same isolated server and
  database: 32 passed in 3.5 minutes.
- Focused browser acceptance after integrating Reports 600f5d7:
  `CI=1 pnpm test tests/advertising-analytics.spec.ts` passed 2 tests in 46.6
  seconds. The first attempt detected transient horizontal overflow during the
  sidebar resize animation; the check now polls for settled geometry.
- A bounded, isolated smoke probe captured 1,200 unique visits across three
  branches and published their report refresh. Reads used 4 SQL queries for
  one branch and 4 for three branches. It exited 1 because the then-current
  Reports implementation counted both `visit` and `session_started` as sessions
  (800/2,400 instead of 400/1,200); a Reports followup is pending before the
  final smoke run.
- After the Reports followup, a fresh `f04_smoke_final` test partition passed:
  1,200 events and 1,200 sessions across three branches; capture p95 10.912 ms,
  report refresh 129.298 ms, and 4 SQL queries for both one-branch and
  three-branch reads. The cutoff index was present. These are bounded local
  smoke timings, not a production capacity estimate.
- `MIX_ENV=test TEST_DB_HOST=127.0.0.1 TEST_DB_PORT=55437
  MIX_TEST_PARTITION=f04qa mix precommit`: passed, including strict Credo
  (0 issues) and 1628 ExUnit tests (0 failures, 7 contract tests excluded).
- Final QA worktree `mix precommit` on the isolated `f04qa2` test partition:
  1660 tests, 0 failures, 7 contract tests excluded; strict Credo found 0 issues.
- Final full browser suite, using `CI=1` and direct Playwright CLI with proxy
  variables cleared against fresh `delivest_e2e_f04final`: 33 passed in 4.1
  minutes. The three new advertising and analytics scenarios all passed.
- Final `pnpm typecheck` in `e2e/` and Node clipboard hook tests: passed; the
  latter ran 2 tests with 0 failures.

Delivery is by push; no pull request is planned.

The first browser attempt could not start because this worktree lacked
`assets/node_modules`. A later attempt used the wrong loopback address for the
client preview (which bound IPv6). Both setup issues were corrected before the
passing run. The first copy test had an overly broad selector matching its status
element; the corrected selector passed. A new boundary test initially used a
second-precision DateTime that Ecto rejected for a microsecond field; it passed
after constructing the same instant with microsecond precision.
One later `pnpm test` attempt timed out before tests because the package manager
injected a proxy into Playwright's health check; direct Playwright CLI with the
proxy variables cleared ran the final suite successfully. The exploratory
smoke failure preceded the Reports session-count correction; the fresh final
smoke run passed.
