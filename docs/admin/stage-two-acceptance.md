# Admin stage two acceptance notes

Source: [admin refactor specification, section 2](https://www.notion.so/41731ec95e4481a19d7ac2a73e1553cd).

## Implemented route and UI contract

- `DelivestWeb.StaffNav` is the source for the primary sidebar, settings navigation, local menu navigation, command palette pages, and feature/provider destinations. The sidebar shows the primary work areas and Settings in its footer. Product, client, delivery, finance, and settings links are local to their sections. Canonical editor routes remain in place.
- The global staff header contains the scope control, command search, and mobile sidebar toggle. Page titles, navigation, and actions render in `main`. The desktop sidebar starts open, its collapsed preference persists, and the mobile drawer overlays content and closes after navigation or Escape.
- Settings opens a persistent menu and a network or selected-branch summary. Host-managed feature gates come from `Features.Registry.features/0` and `Features.snapshot/2`; integration facts come from `IntegrationLive.Presentation` without a new provider request. Status uses effective operations (`:on`), readiness (`:not_ready`/`:paused`), and connection warnings. Saved CRM order-source configuration, credential presence or a successful connection check alone never marks usage enabled. Provider links open existing editors only when authorized.
- Scope transitions are classified by `StaffBranchPath.transition/2`. The URL determines displayed scope; branch lists and settings keep their section, object detail IDs are dropped, compatible filters are preserved, and dashboard fallbacks have explicit labels. Controllers recheck branch access. Role starts are checked in `StaffHomeController`.
- `StaffDirtyGuard` watches explicit `data-staff-dirty` editing forms, blocks staff navigation, history and unload while changed, and shows `#staff-unsaved-dialog`. A successful server save emits `staff:form-saved`; the hook clears only the submitted form baseline. Failed saves retain dirty state. The foundation gallery retains its separate guard.

## Verification coverage

- LiveView tests cover settings permission gates, canonical menu destinations, feature filters and effective integration usage; command search aliases; sidebar/header scope and local navigation; branch URL transitions and role starts.
- Node tests cover dirty navigation cancellation/confirmation, failed-save retention, successful-save clearing, and rearming after another edit.
- The global header selects branch scope for the settings and integration summaries; legacy `?branch=` URLs remain readable. An inaccessible branch query exits to the network summary with a permission flash.
- Inventory is regenerated from the final UI markup; `mix admin.inventory --check` verifies its annotations.

Executed on the stage-two server worktree:

| Command | Result |
| --- | --- |
| `MIX_TEST_PARTITION=_admin_stage2 mix precommit` | Exit 0; 1891 tests, 0 failures, 7 excluded; Credo 0 issues; inventory matched. |
| Targeted staff UI LiveView suite | 83 tests, 0 failures. |
| Targeted scope, settings and navigation suite | 20 tests, 0 failures. |
| `node --test assets/js/hooks/staff_dirty_guard.test.mjs assets/js/hooks/foundation_dirty.test.mjs` | 5 tests, 0 failures. |
| `mix assets.build` | Exit 0. |
| `mix gettext.extract --check-up-to-date` | Exit 0. |
| `git diff --check` | Exit 0. |

The parent agent's final browser pass covered orders, products, the branch-scoped settings summary and network brand at 1440 px and 390 px in light and dark themes (16 cases). Each had one visible `h1`, a 56 px global header, no document overflow and no page errors. Manual review confirmed the desktop settings sidebar exposes the main work areas, a CRM with only saved order sources shows Disabled, and the mobile brand title and local navigation occupy separate rows. Captures are in `/home/kirill/.codex/visualizations/2026/11/13/01a1d655-a5c7-7732-868a-44f961bdfc4f/admin-stage-two` outside the repository; this absolute path is local and not portable.

The parent ran `env -u PLAYWRIGHT_ARGS make preflight` sequentially on the final server code: exit 0, all 71 steps passed without retries (6.3 minutes). The full log is `/tmp/delivest-stage2-preflight-final.log` in the local workspace.

## Specification coverage

| Criterion | Implementation evidence |
| --- | --- |
| 2.1 Global shell | Main-task sidebar, 56px header, page title and local navigation in main, responsive drawer, role start, scoped kitchen indicator. |
| 2.2 Section tree | StaffNav primary and local entries expose the existing order, delivery, menu, client, marketing, finance, analytics and settings routes. |
| 2.3 Scope | URL-based Header/BranchSwitcher, explicit transition policy, guarded forms and server access checks. |
| 2.4 One catalog | StaffNav drives sidebar, settings navigation, local navigation and CommandSearch aliases. |
| 2.5 Settings | Persistent menu and read-only feature/integration summary link to canonical editors. |
| 2.6 Visibility | Catalog read gates and feature gates, provider edit gates, existing route and form authorization. |
| 2.7 Acceptance | Automated navigation, scope, alias and dirty-guard checks, the 16-case visual pass and all 71 parent preflight steps passed on the final local code. |

## Known limits

- The settings feature summary reads saved state; it does not initiate a provider check. It shows the last recorded connection result, and `Connection not checked` remains explicit when no check exists.
- `StaffNav` records read permissions and known feature/gateway dependencies for catalog entries. Edit permissions remain enforced at canonical form actions and route hooks; the catalog does not replace those checks.
- `StaffDirtyGuard` opts in editing forms, including confirmation dialogs with free-text reasons. Search/filter forms, POS controls, and the foundation gallery are excluded. Editors that navigate away or close their form on successful save drop that form; remaining same-page editors emit a save acknowledgment.
- Local stage-two acceptance is complete on the verified code. Runtime feature contracts and background-work validation belong to stage three and are not claimed here.
