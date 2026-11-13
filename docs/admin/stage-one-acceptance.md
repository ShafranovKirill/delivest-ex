# Staff admin foundation: stage 1 evidence

Source specification: [Admin refactor stage 1](https://app.notion.com/p/41731ec95e4481a19d7ac2a73e1553cd). This document records the implementation and checks for review; it does not approve later screen migrations.

## Scope and coverage

| Spec | Stage 1 evidence |
| --- | --- |
| 1.1 Inventory | [Source inventory](inventory.md) and its machine-readable register. It records 96 screens, 393 staff form controls, 678 action records, 19 features/integrations and 71 background jobs. The separate census has 725 schema declarations; 16 service, authentication and internal routes sit outside the four page types. |
| 1.2 Page types | Dev/test gallery demonstrates queue, list, entity and settings pages. |
| 1.3 Visual rules | Opt-in shell tokens and normal/compact density; light/dark and desktop/mobile browser captures. |
| 1.4 Component catalog | [Foundation contracts](foundation-contracts.md) map components and existing adapters, slots/events and client/server ownership. |
| 1.5 Header and navigation | One content `h1` in gallery; existing staff shell with opt-in workspace header, scope and section navigation. |
| 1.6 Tables and filters | URL-backed query, filter, sort, page and 25/50/100 page size; server page selection, reset, empty/no-results and employee/list column preferences. |
| 1.7 Forms and buttons | Dirty, pending, success, errors, conflict and read-only states; explicit leave/cancel and conflict recovery; keyboard dialog/panel behavior. |
| 1.8 Gallery | Authenticated dev/test route `/staff/foundation-gallery`, in-memory fixtures and the checks below. |

## Checks run

- `MIX_TEST_PARTITION=_admin_foundation mix precommit`: exit 0; 1,880 tests, 0 failures, 7 excluded by the existing `:contract` test configuration.
- `MIX_TEST_PARTITION=_admin_foundation mix test test/delivest_web/live/staff/foundation test/delivest_web/live/staff/foundation_components_test.exs test/delivest_web/live/staff/foundation_gallery_live_test.exs`: 28 tests, 0 failures.
- `node --experimental-default-type=module --test assets/js/hooks/foundation_*.test.mjs`: 9 tests, 0 failures.
- Following the last layout-only fix: `MIX_TEST_PARTITION=_admin_foundation mix test test/delivest_web/live/staff/foundation_gallery_live_test.exs:149`: 1 test, 0 failures; `mix format --check-formatted lib/delivest_web/live/staff/foundation_gallery_live.ex`, `mix assets.build` and `git diff --check` exited 0. The full suite was not rerun after that one CSS-class change.

The final browser pass captured all four page types at 1440 px and 390 px in light and dark themes (16 cases). Each had one `h1`, a 56 px header, no document overflow and no page errors. Browser interaction checks covered Back, Stay, confirmed discard, guard reset and rearming, dirty panel, ordinary staff links, column preferences after a LiveView patch and focus return. Captures are in `/home/kirill/.codex/visualizations/2026/11/13/01a1d621-5d1a-7ed3-988c-5adcc8922c1a/admin-foundation` outside the repository; that absolute path is local and not portable.

## Limits carried forward

The inventory is a source census, not proof of runtime authorization, validation or safe disable behavior. The known orphan `close_copy` event in `staff/product_live/copy_component.ex` is marked for deletion during that screen's migration; it was not repaired in stage 1. The gallery uses isolated in-memory fixtures and does not call providers or persist business data. No production staff screen, domain execution gate, permission rule or business validation was migrated. Real screen migrations must validate these contracts against their repository queries, permissions and revision checks in later stages.
