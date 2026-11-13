# Admin stage three acceptance matrix

Source: [admin refactor specification, section 3](https://www.notion.so/41731ec95e4481a19d7ac2a73e1553cd).

The runtime contract reads existing feature gates and provider settings. It does not add a second enable flag. `Delivest.Availability.feature/2` exposes desired and effective state, generation, reason, scope, actions, activity and obligations for host features. `Delivest.Availability.crm/3` exposes the same fields plus order, catalog and stop capabilities. Provider-specific settings remain the authority for other integrations, with poller target checks before enqueue and execution.

| Criterion | Implementation and verification evidence |
| --- | --- |
| 3.1 State model | Availability adapters distinguish saved configuration, desired enable, effective capability, connection check, current issue and work obligations. Frontpad main state uses effective operations and shows Disabled despite a successful saved-config check when sending is off. |
| 3.2 Activity and obligations | CRM summary counts unsent, uncertain and accepted orders; integration cards and detail state show recent journal activity, warnings and available actions. Pending/failed unsent orders expose a manual retry; uncertain sent outcomes keep their reconciliation path. |
| 3.3 Existing switches | Feature/Background paths read the same Features gates. CRM reads BranchSettings; Frontpad credentials save never sets enabled, and the enable/disable action is separate. Empty secret input preserves the saved key. |
| 3.4 Capabilities | CRM orders require enabled, selected provider, credentials and a nonempty source set. Catalog refresh requires active Frontpad CRM; stop sync is checked per provider, including iiko and r_keeper. Frontpad details show orders, automatic catalog and stops separately. Manual credential diagnosis remains available with saved settings. |
| 3.5 UI status | Integration cards, settings center and Frontpad detail use the effective state; connection errors and current warnings take priority over green status. A second open Frontpad LiveView receives settings changes through PubSub and updates without reload. |
| 3.6 Runtime gates | Background dispatcher/runner, CRM producer and SyncWorker, CRM catalog/stops pollers and refresh jobs, generic poller targets/worker, Dadata and YandexEda busy targets, and YandexEda menu reload recheck eligibility. CRM jobs carry settings generation; stale queued jobs are canceled and cannot revive after a later enable. Catalog and stop data publication recheck generation after fetch. |
| 3.7 In-flight work | CRM transitions pending to sending under row lock before HTTP. A duplicate worker cannot submit while the first request is in flight. Queued, unstarted orders canceled by settings changes receive an alert and explicit retry; started/uncertain submissions remain visible and are not automatically resent. Confirmation, command, webhook, fiscal, payment and delivery obligations continue on their persisted operation state. |
| 3.8 No disabled work | Disabled branches leave catalog/stops target lists; repeated producer ticks do not enqueue their catalog jobs while an enabled neighbor remains. Disabled/stale worker tests stub provider HTTP and verify no external request. |
| 3.9 Acceptance | Focused tests cover disabled CRM, stale generation, explicit retry, duplicate in-flight submission, provider stop neighbors, Frontpad second tab, repeated poller ticks and YandexEda menu reload. `mix precommit` and parent `make preflight` are release gates; record their final result below. |

The generated [background inventory](inventory.md) and [semantics map](background-semantics.exs) classify each controlled optional job versus accepted business operation. The generic poller checks current targets, while each provider retains its own domain-specific eligibility and reconciliation rule. Fiscal receipt, payment and delivery jobs represent accepted commitments and are not globally canceled when an editor turns off new work.

## Inventory coverage

The 19 entries in `features_integrations` have the following runtime disposition. A provider-specific completion path is kept for an accepted operation; a disabled setting does not erase that operation.

| Inventory ID | New-work gate and completion obligation | Test evidence |
| --- | --- | --- |
| `feature:analytics_extended` | `Features.enabled?` and Background generation; published report persists. | `features_test.exs`, `background_test.exs`, `analytics_test.exs` |
| `feature:analytics_franchise` | Same feature/Background gate; franchise report persists. | `features_test.exs`, `background_test.exs`, `analytics/reports_test.exs` |
| `feature:analytics_funnel` | Same gate; published funnel remains historical. | `features_test.exs`, `background_test.exs`, `analytics/reports_test.exs` |
| `feature:analytics_links` | Same gate; committed link report remains. | `features_test.exs`, `background_test.exs`, `analytics_test.exs` |
| `feature:marketing_policies` | Feature gate, lifecycle worker generation and publication checkpoint; existing campaign history persists. | `marketing_lifecycle_test.exs`, `marketing_lifecycle_race_test.exs` |
| `feature:notifications` | Feature/source/consent generation gate at delivery; reserved outcome remains recorded. | `notifications_test.exs`, `notifications_concurrency_test.exs` |
| `feature:segments` | Feature/Background generation gate and publish fence; committed segment membership persists. | `segments_test.exs`, `background_test.exs` |
| `integration:atol_online` | Fiscal own-mode target gate; registered receipt poll/callback completes independently. | `fiscal_test.exs`, `atol_online/kkt_poller_test.exs` |
| `integration:dadata` | Active settings make poll targets; suggestions check active config before HTTP. No accepted delivery is created by suggestions. | `dadata_test.exs`, `integration_live/dadata_test.exs` |
| `integration:fiscal` | Fiscal mode gates new registration; persisted receipt state drives completion. | `fiscal_test.exs`, `payments/online_fiscal_test.exs` |
| `integration:frontpad` | CRM provider/orders/catalog/stops capabilities, generation and atomic order claim; sent/uncertain order remains reconciled. | `availability_test.exs`, `crm_test.exs`, `crm/frontpad_stop_refresh_test.exs`, Frontpad LiveView tests |
| `integration:iiko` | CRM capability gate and stop webhook producer target check; accepted order webhook/inbox completes. | `iiko_test.exs`, `crm/commands_test.exs` |
| `integration:rkeeper` | CRM capability gate; sent order polling and accepted status completion persist. | `rkeeper_test.exs`, `crm/commands_test.exs` |
| `integration:routes` | Saved per-channel routing and CRM source set gate new order submission; existing order provider is persisted. | `crm_test.exs`, `iiko_test.exs`, `rkeeper_test.exs` |
| `integration:yandex_delivery` | Active branch targets new polling; claim lookup/receipt of an accepted delivery continues. | `yandex_delivery_test.exs` |
| `integration:yandex_eda` | Enabled branch/credentials targets BusyPoller; MenuReloadWorker carries generation and rechecks before publish. Accepted order events continue. | `yandex_eda/menu_reload_test.exs`, `yandex_eda/busy_mode_test.exs`, `yandex_eda/order_events_test.exs` |
| `integration:ycart` | Existing Ycart branch setting gates entry; persisted cart/order lifecycle remains independent. | `integration_live/ycart_test.exs` |
| `integration:yookassa` | Credentials gate new account work; pending payment reconciliation remains an obligation. | `yookassa_test.exs`, `yookassa/reconciliation_test.exs` |
| `integration:zvonok` | Existing enabled/configured gate for new callback work; accepted callback result remains recorded. | `zvonok_test.exs`, `integration_live/zvonok_test.exs` |

Paths in the test column are relative to `test/delivest/` or `test/delivest_web/live/staff/` as appropriate. This table describes each entry's actual domain gate; the shared CRM adapter is not claimed to govern fiscal, payment, delivery or channel completion workers.

## Verification

| Command | Result |
| --- | --- |
| `MIX_TEST_PARTITION=_admin_stage3 mix test test/delivest/integrations/crm_test.exs test/delivest/integrations/availability_test.exs test/delivest_web/live/staff/integration_live/frontpad_test.exs` | 36 tests, 0 failures. |
| `MIX_TEST_PARTITION=_admin_stage3 mix test test/delivest/integrations/health_test.exs test/delivest_web/live/staff/integration_live/yookassa_test.exs` | 19 tests, 0 failures. |
| `MIX_TEST_PARTITION=_admin_stage3 mix precommit --max-cases 2` | 1907 tests, 0 failures, 7 excluded; compile and Credo passed; source inventory matched. Log: `/tmp/admin-stage3-precommit-final3.log`. |
| `env -u PLAYWRIGHT_ARGS make preflight` | 72 Playwright tests passed, 0 failures. Log: `/tmp/admin-stage3-preflight-final2.log`. |
| Final presentation follow-up | After the full gates, the Frontpad sending control moved above health details and CRM obligation counts were separated. Targeted LiveView suite: 16 tests, 0 failures; `mix assets.build` passed; affected desktop/mobile Playwright test: 1 passed. Logs: `/tmp/admin-stage3-final-ui-targeted.log`, `/tmp/admin-stage3-assets-final.log`, `/tmp/admin-stage3-final-ui-e2e.log`. |
| Translation and drift checks | `mix gettext.extract --check-up-to-date`, `mix admin.inventory --write`, and `git diff --check` passed after source edits. Existing en/ru catalog messages were preserved; only stage-three translations were appended. |

Visual captures of the final Frontpad settings page are `/tmp/admin-stage3-frontpad-desktop.png`, `/tmp/admin-stage3-frontpad-mobile-top.png` and `/tmp/admin-stage3-frontpad-mobile.png`. The mobile capture is 390 px wide after both desktop-to-mobile resize and a fresh mobile page load; the sender control is visible above the health summary. The screenshots were opened and checked for clipping and horizontal overflow.

Previously persisted CRM SyncWorker jobs without a generation are treated as stale queued work. They are canceled on the next settings change; when executed before that, they record a visible unsent failure instead of sending under an unversioned configuration. Operators can retry that specific unstarted order after checking the route. Already accepted or uncertain orders remain on their reconciliation path.
