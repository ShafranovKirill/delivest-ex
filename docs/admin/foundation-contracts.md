# Staff foundation contracts (stage 1)

This is the opt-in contract for later screen migrations. The existing production screens and their execution gates remain in place. The source inventory is `inventory.*` in this directory.

## Page types

| Type | Required content | Gallery variant |
| --- | --- | --- |
| Queue | Context, status, quick action, freshness and connection state. Do not reorder a row while the pointer is on it. | `?view=queue`; a card queue. Kitchen can use a full-screen work mode with the same action and error language. |
| List | One primary action, URL backed search/filter/sort/page, data, scoped selection, pagination, empty/no-results. | `?view=list`; 32 fixture products, server LiveView filtering and paging. |
| Entity | Name/status, key data, related data, history if present, return to prior list URL. | `?view=entity&id=p2&return=…`. |
| Settings | Scope, grouped fields, one save, permissions, dirty/pending/error/conflict feedback. | `?view=settings`; branch fixture form and integration states. |

Normal page title, actions and section navigation render inside content. `staff_app` remains the only shell. `foundation_workspace` opts the gallery into a 56 px header and 240 px desktop sidebar, and suppresses the legacy header h1. The gallery content owns its single h1. Production screen header portals remain until each screen migrates.

## Component catalog

| Responsibility | Component or adapter | Contract |
| --- | --- | --- |
| StaffShell | Existing `Layouts.staff_app`, `StaffHeader`, `StaffSidebar` | Authenticated shell; `foundation_workspace` opt-in for content title. |
| ScopeSwitcher | `FoundationComponents.scope_switcher/1`, existing `StaffNav` branch navigation | Caller supplies authorized options; search emits `scope_search` with 300 ms debounce. Gallery has network and demo branch scopes. Real routing must check staff access. |
| PageHeader | `workspace_header/1`; legacy `CoreComponents.page_header/1` remains | One content h1, description, scope, primary/secondary slots. |
| SectionNav | `section_nav/1`; legacy `header_navigation/1` remains | Caller supplies valid local paths; active item marked `aria-current`; narrow screens scroll. |
| FilterBar | `filter_bar/1`, `ListState` | 350 ms debounce; LiveView pushes URL patch; server re-fetches; reset URL removes conditions. |
| DataTable | `data_table/1` wraps opt-in `CoreComponents.table/1` foundation variant | Caller supplies page rows, columns, optional cell/action slots and paths. Server owns sort/page; checkbox and row actions are separate from the name link. Mobile `More details` reveals secondary fields. Existing table callers keep the legacy variant. |
| BulkActionBar | `bulk_action_bar/1`, `ListState.select/3` | Selection intersects page IDs, clears on URL/scope change; count says “on this page”. Caller validates permissions and IDs again before operation. |
| EntityPicker | Existing `ProductLive.ProductPicker` | Gallery uses it with in-memory fixtures. Parent checks permissions/ownership on persistence; picker callback is draft only. |
| FormSection | `form_section/1` | Semantic group and explanatory text; no independent save. |
| FormActions | `form_actions/1`, `FormState` | Dirty/pending/success/error/conflict/read-only; duplicate submit rejected in helper. Conflict blocks save until caller explicitly loads latest revision for retry or confirms reload. Read-only flag survives error and cancel transitions. |
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

Foundation variables use a 4 px spacing step, 40 px controls, at least 44 px touch targets, 240 px sidebar, 56 px header and 960 px max form width. Normal/compact table density changes padding, not font size. Light and dark themes reuse daisyUI semantic colors. These tokens apply only within `foundation-workspace`/`foundation-shell` until screen migration.

## URL and state ownership

`ListState.from_params/2` allowlists sort fields and filters, bounds page/per-page (25, 50, 100) and discards malformed nested values. `ListState.query/1` supplies a server query contract; no full dataset is sent for browser filtering. Filter, sort, scope or page-size changes reset page to 1 and selection. Page navigation clears selection. The gallery keeps fixtures in module memory, filters and pages on the LiveView server, and uses the list URL as the entity return target. Real domain lists must call their paged repository query and permission check.

`FormState` only describes UI transitions. A successful database result must be passed to `saved/2`; validation errors and server errors keep the draft. Conflict blocks submit until `resolve_conflict/3` receives latest data from the caller, or `reload_latest/2` follows explicit discard confirmation. This helper does not implement optimistic locking: real forms must fetch/check the current revision and enforce server permissions before writing. The gallery uses the existing `Delivest.Identity.Branch.changeset/2` for fixture validation, then simulates successful persistence in memory. It never writes branch data.

The `FoundationDirty` hook intercepts unmodified staff links and Back/Forward while a form is dirty and asks the LiveView to show a leave confirmation. Modified clicks and unrelated links keep normal browser behavior. It also enables the browser's native `beforeunload` prompt for refresh or tab close. The gallery's `handle_params` is a server-side fallback for history patches; it restores the settings URL and shows the confirmation. `confirm_leave` only navigates to a staff path after confirmation and preserves patch versus ordinary navigation behavior; Stay leaves the draft intact. A real form must keep its own saved baseline in sync with confirmed persistence.

The route `/staff/foundation-gallery` is compiled only in dev/test and is inside the authenticated staff live session. Fixture products and integration states make no external calls. Production does not expose the route.
