# Stage four staff administration route audit

This register follows the 96 stage-one screens and the two added routes (`products/:id` and `finance/transactions`): 98 current screens. The [source inventory](inventory.md) is generated; this document records the destination and route-level disposition. “Reused” means the existing domain UI remains under the shared shell. “Migrated” is stated only where the production handler calls a shared component. The scenario column is the behavior to inspect for that handler; the verification log below states what was actually run.

| Route | Type / destination | Handler and component disposition | Scenario |
| --- | --- | --- | --- |
| `/staff/b/:branch_slug/advertising-links` | list / Marketing | `AdvertisingLive.Index::index`; Migrated: shell + StaffNav, page header, dirty guard | branch access; feature disabled |
| `/staff/b/:branch_slug/categories/:id/edit` | entity / Menu | `Categories::edit`; Migrated: shell + StaffNav, page header | list, products, create/edit, branch boundary |
| `/staff/b/:branch_slug/categories/:id/products` | entity / Menu | `Categories::products`; Migrated: shell + StaffNav, page header | list, products, create/edit, branch boundary |
| `/staff/b/:branch_slug/categories/new` | entity / Menu | `Categories::new`; Migrated: shell + StaffNav, page header | list, products, create/edit, branch boundary |
| `/staff/b/:branch_slug/categories` | list / Menu | `Categories::index`; Migrated: shell + StaffNav, page header | list, products, create/edit, branch boundary |
| `/staff/b/:branch_slug/couriers` | work_queue / Delivery | `CourierLive.Board::index`; Migrated: shell + StaffNav, page header | dispatch and handoff by branch |
| `/staff/b/:branch_slug/dashboard` | list / Overview | `DashboardLive.Index::index`; Migrated: shell + StaffNav, page header | network/branch scope |
| `/staff/b/:branch_slug/deliveries` | work_queue / Delivery | `CourierLive.Index::index`; Migrated: shell + StaffNav, page header | dispatch and handoff by branch |
| `/staff/b/:branch_slug/delivery/address` | settings / Settings / Delivery | `DeliveryLive.Address::index`; Migrated: shell + StaffNav, page header, error summary, dirty guard | zone create/reorder/delete, address validation, couriers |
| `/staff/b/:branch_slug/delivery/couriers` | settings / Delivery | `DeliveryLive.Couriers::index`; Migrated: shell + StaffNav, page header, error summary, dirty guard | zone create/reorder/delete, address validation, couriers |
| `/staff/b/:branch_slug/delivery/zones` | settings / Settings / Delivery | `DeliveryLive.Zones::index`; Migrated: shell + StaffNav, page header, dirty guard | zone create/reorder/delete, address validation, couriers |
| `/staff/b/:branch_slug/delivery` | settings / Delivery | `DeliveryLive.Index::index`; Migrated: shell + StaffNav, page header | zone create/reorder/delete, address validation, couriers |
| `/staff/b/:branch_slug/finance/payments` | settings / Finance | `FinanceLive.Payments::index`; Migrated: shell + StaffNav, page header, error summary, dirty guard | settings error/draft; transactions period/search/status/page/order link |
| `/staff/b/:branch_slug/finance/receipts` | list / Finance | `ReceiptLive.Index::index`; Migrated: shell + StaffNav, page header, table, filter bar | local date boundary, pending after CRM owner switch, paging |
| `/staff/b/:branch_slug/finance/transactions` | list / Finance | `FinanceLive.Transactions::index`; Migrated: shell + StaffNav, page header, table, filter bar | settings error/draft; transactions period/search/status/page/order link |
| `/staff/b/:branch_slug/integrations/dadata` | settings / Settings / Integrations | `Dadata::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/fiscal` | settings / Settings / Integrations | `Fiscal::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/frontpad` | settings / Settings / Integrations | `Frontpad::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/iiko` | settings / Settings / Integrations | `Iiko::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/rkeeper` | settings / Settings / Integrations | `Rkeeper::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/routes` | settings / Settings / Integrations | `Routes::index`; Migrated: shell + StaffNav, page header | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/yandex-delivery` | settings / Settings / Integrations | `YandexDelivery::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/yandex-eda` | settings / Settings / Integrations | `YandexEda::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/ycart` | settings / Settings / Integrations | `Ycart::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/yookassa` | settings / Settings / Integrations | `Yookassa::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations/zvonok` | settings / Settings / Integrations | `Zvonok::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/integrations` | settings / Settings / Integrations | `Index::index`; Migrated: shell + StaffNav, page header | provider status, disabled capability, credentials validation |
| `/staff/b/:branch_slug/kitchen` | work_queue / Orders | `KitchenLive.Index::index`; Migrated: shell + StaffNav, page header | ready/undo; feature loss exits and unsubscribes |
| `/staff/b/:branch_slug/loyalty` | settings / Settings / Loyalty | `LoyaltyLive.Index::index`; Migrated: shell + StaffNav, page header, dirty guard | gateway ownership and permissions |
| `/staff/b/:branch_slug/menu/popular` | list / Menu | `Popular::index`; Migrated: shell + StaffNav, page header, dirty guard | branch menu order and navigation |
| `/staff/b/:branch_slug/orders/:id/edit` | entity / Orders | `OrderForm::edit`; Reused existing UI under shell + StaffNav | URL filters, status, payment, card return, revoked write right |
| `/staff/b/:branch_slug/orders/:id` | entity / Orders | `Orders::show`; Migrated: shell + StaffNav, page header | URL filters, status, payment, card return, revoked write right |
| `/staff/b/:branch_slug/orders/new` | entity / Orders | `OrderForm::new`; Reused existing UI under shell + StaffNav | URL filters, status, payment, card return, revoked write right |
| `/staff/b/:branch_slug/orders` | work_queue / Orders | `Orders::index`; Migrated: shell + StaffNav, page header | URL filters, status, payment, card return, revoked write right |
| `/staff/b/:branch_slug/pos` | work_queue / Orders | `PosLive.Index::index`; Migrated: shell + StaffNav, page header | checkout, handout and branch isolation |
| `/staff/b/:branch_slug/products/:id/edit` | entity / Menu | `Products::edit`; Migrated: shell + StaffNav, page header, ProductFormComponent, error summary, dirty guard | edit validation, conflict and filtered return; rights and branch scope |
| `/staff/b/:branch_slug/products/:id` | entity / Menu | `Products::show`; Migrated: shell + StaffNav, page header, read-only product card | read-only grouped fields, edit right and filtered return |
| `/staff/b/:branch_slug/products/bulk` | list / Menu | `Bulk::index`; Migrated: shell + StaffNav, page header, dirty guard | list sort/page, readonly card, editor conflict/rights, stops |
| `/staff/b/:branch_slug/products/modifiers` | list / Menu | `Modifiers::index`; Migrated: shell + StaffNav, page header, dirty guard | list sort/page, readonly card, editor conflict/rights, stops |
| `/staff/b/:branch_slug/products/new` | entity / Menu | `Products::new`; Migrated: shell + StaffNav, page header, ProductFormComponent, error summary | create defaults, validation, rights and return |
| `/staff/b/:branch_slug/products/operations` | list / Menu | `Operations::index`; Migrated: shell + StaffNav, page header, dirty guard | list sort/page, readonly card, editor conflict/rights, stops |
| `/staff/b/:branch_slug/products/stops` | list / Menu | `StopList::index`; Migrated: shell + StaffNav, page header, table and filter bar | search/page, branch stop status and refresh |
| `/staff/b/:branch_slug/products/suggested` | list / Menu | `Suggested::index`; Migrated: shell + StaffNav, page header | list sort/page, readonly card, editor conflict/rights, stops |
| `/staff/b/:branch_slug/products/tags/:id/edit` | entity / Menu | `Tags::edit`; Migrated: shell + StaffNav, page header; existing tag editor | tag validation and branch return |
| `/staff/b/:branch_slug/products/tags/new` | entity / Menu | `Tags::new`; Migrated: shell + StaffNav, page header; existing tag editor | tag create validation |
| `/staff/b/:branch_slug/products/tags` | list / Menu | `Tags::index`; Migrated: shell + StaffNav, page header; existing tag list | tag navigation and branch rights |
| `/staff/b/:branch_slug/products` | list / Menu | `Products::index`; Migrated: shell + StaffNav, page header, table and filter bar | sort/page, visible columns, bulk rights and filtered card return |
| `/staff/b/:branch_slug/promotions/:id/codes` | entity / Marketing | `Promotions::codes`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions/:id/edit` | entity / Marketing | `Promotions::edit`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions/new/first-order` | list / Marketing | `Promotions::first_order`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions/new/full` | list / Marketing | `Promotions::full`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions/new` | entity / Marketing | `Promotions::new`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions/sale` | list / Marketing | `Promotions::sale`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/promotions` | list / Marketing | `Promotions::index`; Migrated: shell + StaffNav, page header | status, effective dates, issuance and rights |
| `/staff/b/:branch_slug/statistics` | list / Analytics | `StatisticsLive.Index::index`; Migrated: shell + StaffNav, page header, table | empty/zero/disabled, scope and report filters |
| `/staff/b/:branch_slug/stocks/:id/edit` | entity / Marketing | `Stocks::edit`; Migrated: shell + StaffNav, page header | banner media save/validation and rights |
| `/staff/b/:branch_slug/stocks/new` | entity / Marketing | `Stocks::new`; Migrated: shell + StaffNav, page header | banner media save/validation and rights |
| `/staff/b/:branch_slug/stocks` | list / Marketing | `Stocks::index`; Migrated: shell + StaffNav, page header | banner media save/validation and rights |
| `/staff/branches/:slug/edit/:section` | settings / Settings / Branches | `Edit::section`; Migrated: shell + StaffNav, page header, dirty guard | settings conflict/draft, snapshot target, delete confirm |
| `/staff/branches/:slug/edit` | settings / Settings / Branches | `Edit::edit`; Migrated: shell + StaffNav, page header, dirty guard | settings conflict/draft, snapshot target, delete confirm |
| `/staff/branches/new` | settings / Settings / Branches | `Edit::new`; Migrated: shell + StaffNav, page header, dirty guard | settings conflict/draft, snapshot target, delete confirm |
| `/staff/branches/select` | list / Settings / Branches | `BranchLive.BranchSelect::index`; Migrated: shell + StaffNav, page header | settings conflict/draft, snapshot target, delete confirm |
| `/staff/branches` | list / Settings / Branches | `Branches::index`; Migrated: shell + StaffNav, page header | settings conflict/draft, snapshot target, delete confirm |
| `/staff/clients/:id/edit` | entity / Clients | `Clients::edit`; Migrated: shell + StaffNav, page header, ClientFormComponent | edit validation, rights and filtered return |
| `/staff/clients/:id` | entity / Clients | `Show::show`; Migrated: shell + StaffNav, page header, dirty guard | query return, finance rights, loyalty, edit/delete |
| `/staff/clients/new` | entity / Clients | `Clients::new`; Migrated: shell + StaffNav, page header, ClientFormComponent | create validation and list return |
| `/staff/clients` | list / Clients | `Clients::index`; Migrated: shell + StaffNav, page header, table and filter bar | URL search/status/page, empty result and show return |
| `/staff/dashboard` | list / Overview | `DashboardLive.Index::all`; Migrated: shell + StaffNav, page header | network/branch scope |
| `/staff/diagnostics` | list / Settings / Data and system | `DiagnosticsLive.Index::index`; Migrated: shell + StaffNav, page header | filter and scope |
| `/staff/employee/:id/edit` | entity / Settings / Team and access | `Staffs::edit`; Migrated: shell + StaffNav, page header, StaffFormComponent, error summary, dirty guard | edit, delegated rights, branch scope and source row return |
| `/staff/employee/new` | entity / Settings / Team and access | `Staffs::new`; Migrated: shell + StaffNav, page header, StaffFormComponent, error summary, dirty guard | create, delegated rights, branch scope and list return |
| `/staff/employee` | list / Settings / Team and access | `Staffs::index`; Migrated: shell + StaffNav, page header, table, filter bar | create/edit, delegated rights, branch scope |
| `/staff/franchise/:section` | settings / Settings / Network and brand | `Index::section`; Migrated: shell + StaffNav, page header | section target, documents, danger confirm |
| `/staff/franchise/documents/:kind` | settings / Settings / Network and brand | `Index::document`; Migrated: shell + StaffNav, page header | section target, documents, danger confirm |
| `/staff/franchise` | settings / Settings / Network and brand | `Index::index`; Migrated: shell + StaffNav, page header | section target, documents, danger confirm |
| `/staff/integrations/dadata` | settings / Settings / Integrations | `Dadata::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/integrations/yandex-eda` | settings / Settings / Integrations | `YandexEdaShared::index`; Migrated: shell + StaffNav, page header | provider status, disabled capability, credentials validation |
| `/staff/integrations/yookassa` | settings / Settings / Integrations | `Yookassa::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/integrations/zvonok` | settings / Settings / Integrations | `Zvonok::index`; Migrated: shell + StaffNav, page header, dirty guard | provider status, disabled capability, credentials validation |
| `/staff/integrations` | settings / Settings / Integrations | `Index::index`; Migrated: shell + StaffNav, page header | provider status, disabled capability, credentials validation |
| `/staff/logs/errors` | list / Settings / Data and system | `Index::errors`; Migrated: shell + StaffNav, page header | event/error/raw filters and detail |
| `/staff/logs/raw` | list / Settings / Data and system | `Index::raw`; Migrated: shell + StaffNav, page header | event/error/raw filters and detail |
| `/staff/logs` | list / Settings / Data and system | `Index::events`; Migrated: shell + StaffNav, page header | event/error/raw filters and detail |
| `/staff/marketing/:id/edit` | entity / Marketing | `Index::edit`; Migrated: shell + StaffNav, page header, policy editor | policy validation, scope, dependencies and return |
| `/staff/marketing/:id` | entity / Marketing | `Index::show`; Migrated: shell + StaffNav, page header, policy detail | effective dates, publication and edit right |
| `/staff/marketing/bonuses` | settings / Settings / Loyalty | `MarketingLive.Bonuses::index`; Migrated: shell + StaffNav, page header | hub/branch navigation, policies and bonus scope |
| `/staff/marketing/new` | entity / Marketing | `Index::new`; Migrated: shell + StaffNav, page header, policy editor | policy defaults, scope, validation and save |
| `/staff/marketing/policies` | list / Marketing | `Index::index`; Migrated: shell + StaffNav, page header; existing policy list | network/branch scope, filters and policy navigation |
| `/staff/marketing` | list / Marketing | `Hub::index`; Migrated: shell + StaffNav, page header | hub/branch navigation, policies and bonus scope |
| `/staff/roles/:id/edit` | entity / Settings / Team and access | `Roles::edit`; Migrated: shell + StaffNav, page header | create/edit, delegated permission guard |
| `/staff/roles/new` | entity / Settings / Team and access | `Roles::new`; Migrated: shell + StaffNav, page header | create/edit, delegated permission guard |
| `/staff/roles` | list / Settings / Team and access | `Roles::index`; Migrated: shell + StaffNav, page header | create/edit, delegated permission guard |
| `/staff/segments/:id/edit` | entity / Clients | `Index::edit`; Migrated: shell + StaffNav, page header, dirty guard | list/card/editor return, rules and members |
| `/staff/segments/:id` | entity / Clients | `Index::show`; Migrated: shell + StaffNav, page header, dirty guard | list/card/editor return, rules and members |
| `/staff/segments/new` | entity / Clients | `Index::new`; Migrated: shell + StaffNav, page header, dirty guard | list/card/editor return, rules and members |
| `/staff/segments` | list / Clients | `Index::index`; Migrated: shell + StaffNav, page header, dirty guard | list/card/editor return, rules and members |
| `/staff/settings` | settings / Settings | `SettingsLive.Index::index`; Migrated: shell + StaffNav, page header | canonical section links |
| `/staff/statistics` | list / Analytics | `StatisticsLive.Index::index`; Migrated: shell + StaffNav, page header, table | empty/zero/disabled, scope and report filters |

## Handler and form ownership

The per-route rows above preserve distinct handlers even when several URLs share one LiveView. The [form owner map](form-owners.exs) assigns every source form to a canonical domain operation and editor. The static inventory records 98 routes, 402 controls and 695 actions; it is a source census, not a claim that every action was clicked in a browser. The two fields removed with `product_live/copy_component.ex` (scope and target branch) belong to the ProductLive.Operations copy flow, where branch selection remains available; that component also had an unhandled `close_copy` event. The product creation matrix keeps short and bulk creation false; existing domain import and copy flows remain explicit operations. The new transactions list is a read-only query form; the receipt list already existed and gained filters and paging. Existing provider settings forms retain their domain validation and gate; a shared shell does not imply a changed provider contract.

Product, role and staff links navigate to full pages and retain the source list query and row fragment for return. Their target IDs carry `scroll-mt-24` so the fixed header does not cover the restored row. The product read-only card has a disabled editor with readable scoped controls and no upload action. The production shell uses 40 px minimum controls on desktop and 44 px controls on mobile; this includes small order queue actions.

## Verification and limits

- `mix test` targeted branch settings, orders, POS, kitchen, delivery, client and segment files: 84 tests, 0 failures (2026-11-14). Branch settings includes stale edit and revoked permission; orders include URL filters.
- Common navigation targeted: 12 tests, 0 failures. The marketing hub and section routes use one `StaffNav` section tree.
- Fiscal receipts: local date boundary, 26-row page, malformed query, tenant separation and pending obligations after CRM owner switch passed in targeted run.
- Finance transactions: branch scope, filters, order link rights and page size passed in targeted run.
- Product full-page navigation, row return and read-only behavior: the owning worker's targeted 38 tests passed; product header and row actions had 27 targeted passes before the final navigation edit. The final browser suite passed after the navigation edit.
- A seeded 390 px browser measurement found 44 px order card action buttons and no document overflow after production shell token adoption. The Analytics source table scrolls inside its wrapper; the first full browser run passed its mobile overflow poll and failed a stale franchise table selector, which the owning worker updated.
- Final server gate: `ERL_FLAGS='+S 4:4' MIX_TEST_PARTITION=_admin_stage4 mix precommit --max-cases 2` completed with 1,946 tests, 0 failures and 7 excluded standard provider live contract tests; inventory matched current sources and Credo found 0 issues in 1,042 files (local log: `admin-stage4-precommit-final5.log`). `mix dialyzer` completed with the existing two configured skips (local log: `admin-stage4-dialyzer-final3.log`); JS hook tests passed 13/13.
- Final browser gate: seeded database setup, `cd client && CI=1 pnpm install --frozen-lockfile && pnpm type-check`, `cd e2e && CI=1 pnpm install --frozen-lockfile && pnpm typecheck && pnpm exec playwright install chromium`, then `cd e2e && CI=1 pnpm exec playwright test --retries=0` completed. Client and browser builds succeeded; 77/77 Playwright tests passed with 0 retries in 6.6 minutes (local log: `admin-stage4-preflight-final4.log`). The working-pages matrix captured orders, clients, receipts, analytics and settings at desktop/mobile in light/dark themes (20 screenshots); the product read-only/edit views added four captures. Those key pages had no observed page errors or document overflow. This is representative UI coverage, not a browser click of all 695 inventoried actions.
- One earlier POS browser run observed fiscal completion after about 74 seconds: one receipt reached `done` on RegisterWorker attempt 1, with no worker error. The cause of queue delay was not established. Only the POS E2E per-test timeout (180 seconds) and bounded wait (120 seconds) changed; the `Пробит` assertion remains, and no backend optimization is claimed. The final POS case passed in 47.7 seconds as part of the 77/77 browser run.
- The seven excluded provider live contract tests are the existing standard exclusion. Production provider behavior was not tested by these gates.
