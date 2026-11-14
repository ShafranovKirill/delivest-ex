# Staff foundation contracts

The foundation gallery established these contracts in stage 1. Stage 4 applies the shared shell, page header, table, filters, navigation, and form feedback on production staff screens where the domain UI uses them. The source inventory is `inventory.*` in this directory; [stage-four acceptance](stage-four-acceptance.md) records each route's disposition. Domain queries, writes, permissions, and execution gates remain owned by their existing modules.

## Page types

| Type | Required content | Gallery variant |
| --- | --- | --- |
| Queue | Context, status, quick action, freshness and connection state. Do not reorder a row while the pointer is on it. | `?view=queue`; a card queue. Kitchen can use a full-screen work mode with the same action and error language. |
| List | One primary action, URL backed search/filter/sort/page, data, scoped selection, pagination, empty/no-results. | `?view=list`; 32 fixture products, server LiveView filtering and paging. |
| Entity | Name/status, key data, related data, history if present, return to prior list URL. | `?view=entity&id=p2&return=…`. |
| Settings | Scope, grouped fields, one save, permissions, dirty/pending/error/conflict feedback. | `?view=settings`; branch fixture form and integration states. |

Normal page title, actions and section navigation render inside content. `staff_app` is the shell for production and gallery pages. `foundation_workspace` remains a gallery hint; production uses `foundation-shell` tokens. The gallery and migrated screens own their content heading. The shared `StaffNav` renders section navigation in the shell.

## Component catalog

| Responsibility | Component or adapter | Contract |
| --- | --- | --- |
| StaffShell | Existing `Layouts.staff_app`, `StaffHeader`, `StaffSidebar` | Authenticated shell and common tokens. |
| ScopeSwitcher | `FoundationComponents.scope_switcher/1`, existing `StaffNav` branch navigation | Caller supplies authorized options; search emits `scope_search` with 300 ms debounce. Gallery has network and demo branch scopes. Real routing must check staff access. |
| PageHeader | `CoreComponents.page_header/1`, `workspace_header/1` | One content h1, subtitle, scope and actions. |
| SectionNav | `StaffNav.local_navigation/1`, `section_nav/1` | Canonical production section tree, active `aria-current`, scroll on narrow screens. |
| FilterBar | `filter_bar/1`, `ListState` | Search and filters share one form, 350 ms debounce; LiveView pushes URL patch and server re-fetches. Reset is shown for active conditions. |
| DataTable | `CoreComponents.table/1`, `data_table/1` adapter | One table implementation for Flop streams and foundation lists. Caller supplies rows, metadata, columns and paths. Server owns sort/page; numeric values align, secondary columns have employee/list preference and mobile detail disclosure. |
| BulkActionBar | `bulk_action_bar/1`, `ListState.select/3` | Selection intersects page IDs, clears on URL/scope change; count says “on this page”. Caller validates permissions and IDs again before operation. |
| EntityPicker | Existing `ProductLive.ProductPicker` | Gallery uses it with in-memory fixtures. Parent checks permissions/ownership on persistence; picker callback is draft only. |
| FormSection | `form_section/1` | Semantic group and explanatory text; no independent save. |
| FormActions | `form_actions/1`, `error_summary/1`, `FormState`, `StaffDirtyGuard` | Existing forms own writes. Opt-in edit buttons disable when pristine; validation errors link to fields; server errors retain entered draft. Branch settings compare editable baseline inside a transaction and require explicit reload on conflict. |
| StatusBadge | `status_badge/1` | Text plus semantic tone; domain statuses stay with domain owner. |
| FeatureCard / FeatureControl | `feature_card/1` with `:action` slot | Caller supplies desired/effective values, blocking reason and server-owned action; gallery toggles a fixture request only. No feature gate changes. |
| IntegrationCard | `integration_card/1` | Configured, desired, effective, connection state/summary, capability states, dependencies, issues and obligations separately visible; optional action slot. Connection `unknown/checking/ok/error/stale` is presentation data supplied by the caller and does not change desired/effective. Gallery check/result actions only transition a fixture, without a provider call. |
| ConfirmDialog | `confirm_dialog/1`, `FoundationDialog` hook | Object/scope, consequences, explicit action; Escape cancels, pending action disabled. |
| SidePanel | `side_panel/1`, `FoundationDialog` hook | Short task only; focus trapped, Escape uses dirty guard, opener focus restored. |

| Empty/Error/Loading | Existing `CoreComponents.empty_state/1`, `state_notice/1` | Separate no-records/no-results, alert/status roles. |
| Address/Money/Phone | `address_field/1` delegates `BranchLive.LocationFields`; `domain_field/1` delegates `CoreComponents.input/1` | Money displays via `Delivest.Money.input/1`, phone uses `tel`; existing changesets own normalization, validation and persistence. |
| ScheduleEditor | `schedule_editor/1` adapter to `BranchLive.WorkingHoursComponent` | Existing branch form normalizes/validates schedule. |
| Column preference | `column_chooser/1`, `FoundationColumns` hook | Browser storage key includes employee ID and list ID; only visible column keys stored. URL conditions and server row query are untouched. |

Event-bearing controls accept an optional `target` (`@myself` or a component selector) for LiveComponent callers: filter and scope forms, row selection in `DataTable`/`Core.table`, cancel in `FormActions`, and dialog/panel buttons. `FormActions` submit remains owned by the caller's form; actions passed through slots supply their own `phx-target` or `JS.push(target: @myself)`. Dialog Escape sends to the owning component when `target` is set.

Foundation variables use a 4 px spacing step, 40 px controls, at least 44 px touch targets, 240 px sidebar, 56 px header and 960 px max form width. Normal/compact table density changes padding, not font size. Light and dark themes reuse daisyUI semantic colors. `foundation-shell` applies these tokens to production staff pages.

The production shell applies 40 px minimum controls on desktop and 44 px buttons, inputs and selects at mobile widths. Square buttons are at least 44 px wide on mobile. Read-only product cards keep native disabled semantics while their scoped text remains readable. Flop pagination offers the page sizes selected by the caller and includes a valid current legacy size (for example 10 or 20) when an old URL requests it.

## URL and state ownership

`ListState.from_params/2` allowlists sort fields and filters, bounds page/per-page (25, 50, 100) and discards malformed nested values. `ListState.query/1` supplies a server query contract; no full dataset is sent for browser filtering. Filter, sort, scope or page-size changes reset page to 1 and selection. Page navigation clears selection. The gallery keeps fixtures in module memory, filters and pages on the LiveView server, and uses the list URL as the entity return target. Real domain lists must call their paged repository query and permission check.

`FormState` only describes UI transitions. A successful database result must be passed to `saved/2`; validation errors and server errors keep the draft. Conflict blocks submit until `resolve_conflict/3` receives latest data from the caller, or `reload_latest/2` follows explicit discard confirmation. This helper does not implement optimistic locking: real forms must fetch/check the current revision and enforce server permissions before writing. The gallery uses the existing `Delivest.Identity.Branch.changeset/2` for fixture validation, then simulates successful persistence in memory. It never writes branch data.

The `FoundationDirty` hook intercepts unmodified staff links and Back/Forward while a form is dirty and asks the LiveView to show a leave confirmation. Modified clicks and unrelated links keep normal browser behavior. It also enables the browser's native `beforeunload` prompt for refresh or tab close. The gallery's `handle_params` is a server-side fallback for history patches; it restores the settings URL and shows the confirmation. `confirm_leave` only navigates to a staff path after confirmation and preserves patch versus ordinary navigation behavior; Stay leaves the draft intact. A real form must keep its own saved baseline in sync with confirmed persistence.

The route `/staff/foundation-gallery` is compiled only in dev/test and is inside the authenticated staff live session. Fixture products and integration states make no external calls. Production does not expose the route.
