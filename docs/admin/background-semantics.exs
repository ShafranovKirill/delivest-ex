%{
  "worker:Delivest.Background.Dispatcher" =>
    {"No external call; enumerates due optional calculations",
     "Background scheduling checks Features.snapshot for each registry feature",
     "Feature.disable triggers Background.feature_changed; dispatcher skips disabled scope",
     "Due schedule may already have Runner job; Runner checkpoint cancels disabled generation"},
  "worker:Delivest.Background.Runner" =>
    {"Runs registry handler; some handlers enqueue child workers with external provider calls",
     "Background.checkpoint before handler, then Background.publish/Features fencing in handlers",
     "Disabled generation returns cancel; handler on_disable callback only where listed",
     "Committed outputs already published remain; in-flight handler must fence its publication"},
  "worker:Delivest.Events.DeliverWorker" =>
    {"Subscriber callback may call CRM, push or other external provider",
     "Event registry and delivery status; no global feature gate in worker",
     "No feature disable callback; delivery persists until subscriber-specific result",
     "Pending/retryable event delivery must reach delivered, failed or explicit cancellation; unknown external outcome is retried"},
  "worker:Delivest.Fiscal.PollWorker" =>
    {"Fiscal.poll_receipt queries provider receipt status",
     "Receipt exists and Fiscal polling path checks provider state; no feature gate in worker",
     "No global feature disable callback",
     "Issued receipt needs terminal fiscal status even if editor configuration later changes"},
  "worker:Delivest.Fiscal.RegisterWorker" =>
    {"Fiscal.register_receipt submits fiscal receipt to provider",
     "Receipt state and Fiscal provider checks; no feature gate in worker",
     "No global feature disable callback",
     "Submitted receipt can be externally accepted before local result; snooze/retry or terminal error must reconcile"},
  "worker:Delivest.Integrations.Crm.CommandWorker" =>
    {"Crm.cancel/update order command to active provider",
     "Rechecks order sent state, provider identity and command token",
     "Provider change marks command failed; no broad queue purge",
     "Unknown external outcome is recorded as unknown; never blindly replay a successful command"},
  "worker:Delivest.Integrations.Crm.ConfirmWorker" =>
    {"CRM order confirmation check via Crm/SyncState",
     "Order and current CRM settings checked in call path", "No disable callback in worker",
     "Unconfirmed sent order remains retryable/visible until confirmation or failure"},
  "worker:Delivest.Integrations.Crm.FrontpadStopRefresh.RefreshJob" =>
    {"Frontpad stop-list fetch via StopSync",
     "FrontpadStopRefresh eligibility and provider stop-sync settings",
     "No feature gate; changed provider/disabled stop sync must make refresh ineligible",
     "Recorded daily refresh run must finish/retry/mark failure; do not erase previous stop state silently"},
  "worker:Delivest.Integrations.Crm.SyncWorker" =>
    {"Sends order to selected CRM provider",
     "CRM availability generation and atomic pending-to-sending claim are checked before delivery",
     "Settings changes cancel stale queued jobs and expose an explicit unsent retry",
     "Started request is not automatically replayed; unresolved external outcome becomes visible unknown"},
  "worker:Delivest.Integrations.Inbox.Worker" =>
    {"Calls provider inbox handler for received webhook/message",
     "Message and handler lookup; no global feature gate in worker",
     "No global disable callback; handler decides provider-specific eligibility",
     "Persisted inbox message records retry/terminal status; accepted provider event must not disappear on disable"},
  "worker:Delivest.Integrations.Poller.Worker" =>
    {"Delegates provider-specific poll; see poller entries",
     "Poller.fetch plus targets/interval; each poller gate listed separately",
     "No global cancel; target lists may become empty and existing target jobs still recheck in poll",
     "Provider reconciliation/poll outcomes must settle or remain retryable; see individual poller"},
  "worker:Delivest.Integrations.Rkeeper.PollWorker" =>
    {"Rkeeper.poll_order queries provider order state",
     "Rkeeper.poll_order uses current order/provider state", "No global disable callback",
     "Sent order remains externally active; poll outcome must reconcile even after setting changes"},
  "worker:Delivest.Integrations.YandexDelivery.ClaimLookupWorker" =>
    {"Api.search claim by order number",
     "Delivery must remain :searching without external_id; token read from branch settings, no enabled gate",
     "No disable callback; retries until lookup window then Couriers.give_up",
     "Claim may already exist externally; lookup must attach external_id or record give-up before new delivery attempt"},
  "worker:Delivest.Integrations.YandexEda.AcceptDeadlineWorker" =>
    {"No provider HTTP call; checks unaccepted order deadline and notifies",
     "Order state/deadline check; no feature gate", "No disable callback",
     "Accepted order deadline obligation persists; notify only if still unaccepted"},
  "worker:Delivest.Integrations.YandexEda.MenuReloadWorker" =>
    {"PushApi.reload_menu external request",
     "Branch enable and generation plus shared PushApi configuration are checked before call",
     "Branch settings changes cancel stale queued reload jobs",
     "An already started request may complete remotely; no automatic replay after enable"},
  "worker:Delivest.Logs.PruneWorker" =>
    {"No provider call; prunes logs, audit, journal and related retention data",
     "Unconditional maintenance task", "No feature disable callback",
     "Pruning already committed cannot be undone; queued run should complete or retry"},
  "worker:Delivest.Loyalty.ExpireWorker" =>
    {"No provider call; expires loyalty entries", "Due-entry check, no feature gate",
     "No feature disable callback",
     "Already accrued points retain ledger history; expiration run may snooze until due entries settle"},
  "worker:Delivest.Loyalty.ExpiryDeliveryWorker" =>
    {"Web push expiry notification through subscription",
     "Subscription and delivery state checks; no feature gate", "No feature disable callback",
     "HTTP outcome may be unknown; delivery row records delivered/failed/unknown and avoids false success"},
  "worker:Delivest.Loyalty.ExpiryNoticeWorker" =>
    {"No direct provider call; enqueues expiry push deliveries",
     "Franchise loyalty settings and due entries checked in worker",
     "No feature disable callback",
     "Queued expiry notices/deliveries must finish or record skipped/expired; no silent deletion"},
  "worker:Delivest.Maintenance.DailyJob" =>
    {"Runs selected Maintenance.Registry task; child may call provider",
     "Registry.resolve validates key/scope, not a feature gate", "No global disable callback",
     "DailyRun tracks scheduled/running/retrying/failed; dispatch reconciliation must preserve terminal result"},
  "worker:Delivest.Maintenance.DispatchWorker" =>
    {"No provider call; schedules DailyJob from registry",
     "Registry tasks/scopes and local due date; not feature-gated",
     "Removed registry task prevents new run, existing DailyJob still resolves key",
     "DailyRun and active Oban job are reconciled; avoid duplicate local-day operation"},
  "worker:Delivest.Media.Workers.ThumbnailBackfillWorker" =>
    {"No provider call; enqueues missing thumbnail jobs",
     "Missing thumbnail query; no feature gate", "No feature disable callback",
     "Already enqueued thumbnail jobs complete independently; source files remain"},
  "worker:Delivest.Media.Workers.ThumbnailWorker" =>
    {"Thumbnails.store reads source and writes WebP via ExAws.S3, then updates DB thumb_key (media/thumbnails.ex:19-26)",
     "Media file exists/valid; no feature gate", "No feature disable callback",
     "S3 write may succeed before DB update; retry must reconcile object key, invalid images cancel"},
  "worker:Delivest.Notifications.DeliverWorker" =>
    {"Delivery transport for queued notification intent",
     "Features.with_enabled_many and generation/current_source/consent checks",
     "Disabled/source-inactive intent marked canceled; no external send after gate loss",
     "In-flight send reserves intent; external success must be recorded without claiming canceled delivery"},
  "worker:Delivest.Notifications.PushDeliveryWorker" =>
    {"Web push delivery for notification",
     "Features.with_enabled_many, generation and current source checks",
     "Disabled/source-inactive delivery canceled; Dispatch.on_disable cancels queued state",
     "Unknown push outcome retained in delivery row; limiter/reservation must settle"},
  "worker:Delivest.Oms.Kitchen.DispatchWorker" =>
    {"No provider call; schedules kitchen jobs due now",
     "Kitchen.dispatch_due selects due orders, no feature gate", "No feature disable callback",
     "Already queued send/ready jobs recheck order state; accepted order still needs kitchen outcome"},
  "worker:Delivest.Oms.Kitchen.ReadyWorker" =>
    {"Kitchen marks/announces ready order; downstream notification may be external",
     "Kitchen.ready_due checks order state and staff; no feature gate",
     "No feature disable callback",
     "Ready transition is business state; cancel only when order state makes it obsolete"},
  "worker:Delivest.Oms.Kitchen.ReplanBranchWorker" =>
    {"No provider call; replans kitchen times for branch",
     "Branch/order state in Kitchen.replan_branch; no feature gate",
     "No feature disable callback",
     "Existing kitchen jobs need replacement/reconciliation after replan"},
  "worker:Delivest.Oms.Kitchen.SendWorker" =>
    {"Kitchen.send_due dispatches order to kitchen; may notify downstream",
     "Kitchen.send_due checks due/order state; no feature gate", "No feature disable callback",
     "Sent order must not be duplicated on retry; order state is authority"},
  "worker:Delivest.Oms.Workers.CartCleanupWorker" =>
    {"No provider call; deletes stale carts/orders", "Age/status query, no feature gate",
     "No feature disable callback",
     "Deletion is irreversible; active checkout must be excluded by query and transaction"},
  "worker:Delivest.Oms.Workers.StaleOrderWorker" =>
    {"No direct provider call; advances stale orders",
     "Past-day/order status query, no feature gate", "No feature disable callback",
     "Completion/cancellation triggers order lifecycle effects; no silent loss of in-flight orders"},
  "worker:Delivest.Payments.Online.PollWorker" =>
    {"Yookassa payment status query through Online", "Yookassa.configured? before polling",
     "Unconfigured path skips new poll, no cancellation callback",
     "Submitted payment must retain pending state and reconcile when connection returns"},
  "worker:Delivest.Payments.Online.RefundWorker" =>
    {"Online refund request to payment provider",
     "Refund record/state checked; no feature gate in worker",
     "Missing refund cancels; no global disable callback",
     "Provider may refund before local acknowledgment; refund state/idempotency must reconcile"},
  "worker:Delivest.Popular.RefreshWorker" =>
    {"No provider call; computes popular-product entries",
     "Popular.Settings/branch schedule checks, no Features gate", "No feature disable callback",
     "Previously published popular entries persist until refresh/explicit setting change"},
  "worker:Delivest.Push.NoteWorker" =>
    {"Web push order note to subscriptions", "Order/subscription checks; no global feature gate",
     "No feature disable callback",
     "Queued note may be delivered after order change; subscription send result must be recorded"},
  "worker:Delivest.Push.StaffWorker" =>
    {"Staff web push for allowlisted order/delivery events",
     "Event allowlist and StaffDispatch recipient selection", "No feature disable callback",
     "In-flight push may already have reached device; retry must avoid claiming guaranteed once-only delivery"},
  "worker:Delivest.Push.Worker" =>
    {"Client web push for order update through Dispatch.run",
     "Order/subscription checks in Dispatch; no global feature gate",
     "No feature disable callback",
     "Pending push may outlive source status; Dispatch result/retry must be observed"},
  "optional:analytics.funnel" =>
    {"No external provider; computes funnel report in database",
     "Features snapshot analytics_funnel, Background checkpoint/publication fence",
     "No handler on_disable; future/queued runs canceled by generation",
     "Published report remains as historical snapshot; in-flight publish must fence generation"},
  "optional:analytics.links" =>
    {"No external provider; computes advertising link report in database",
     "Features snapshot analytics_links, Background checkpoint/publication fence",
     "No handler on_disable; future/queued runs canceled by generation",
     "Published report remains; in-flight publish must fence generation"},
  "optional:analytics.extended" =>
    {"No external provider; computes extended report in database",
     "Features snapshot analytics_extended, Background checkpoint/publication fence",
     "No handler on_disable; future/queued runs canceled by generation",
     "Published report remains; in-flight publish must fence generation"},
  "optional:marketing.preview" =>
    {"No provider call; computes preview candidates in database",
     "marketing_policies dependency closure and Background publication fence",
     "No handler on_disable; future/queued runs canceled by generation",
     "Preview rows may persist but must be versioned/stale on policy revision"},
  "optional:marketing.report" =>
    {"No provider call; aggregates policy delivery report",
     "Features.snapshot/with_enabled marketing_policies plus Background checkpoint",
     "No handler on_disable; queued run canceled by generation",
     "Committed report remains historical; in-flight publication must fence generation"},
  "optional:notifications.dispatch" =>
    {"No direct provider call; enqueues delivery workers that call transports",
     "notifications feature snapshot and send locks in Dispatch/children",
     "Dispatch.on_disable cancels queued intents/deliveries and reservations",
     "In-flight transport may have external outcome; child delivery rows must record it before terminal state"},
  "optional:marketing.evaluate" =>
    {"No provider call; evaluates marketing policy and creates intents",
     "marketing_policies dependency closure and Background publication fence",
     "No handler on_disable; future/queued runs canceled by generation",
     "Already issued rewards/intents remain obligations; evaluation state avoids duplicate issue"},
  "optional:segments.refresh" =>
    {"No provider call; recomputes dynamic segment membership",
     "Features.enabled?/snapshot/still_enabled and Background.publish",
     "No handler on_disable; queued run canceled by generation",
     "Existing membership remains until safe fenced replacement; no partial publication"},
  "poller:Delivest.Integrations.YandexDelivery.Poller" =>
    {"Yandex Delivery claim/status API",
     "targets = YandexDelivery.active_branches; poll rechecks branch state",
     "Inactive branch drops from future target list",
     "Existing delivery claim must reconcile externally before terminal state"},
  "poller:Delivest.Integrations.Crm.StopPoller" =>
    {"For Frontpad with stop sync off: StopSync.clear_frontpad; for other providers: StopSync.sync; active Frontpad stop refresh is separate FrontpadStopRefresh job (crm/stop_poller.ex:15-41)",
     "targets reject Frontpad branches where stops_enabled?/1 true; poll rechecks provider",
     "Frontpad stop sync off clears local stop state; active Frontpad handled by separate refresh job",
     "Cleared local stop state and other-provider sync results are committed operations; pending Frontpad refresh remains separate"},
  "poller:Delivest.Integrations.Crm.CatalogPoller" =>
    {"Catalog.refresh(branch_id, :frontpad) and Health report (crm/catalog_poller.ex:21-39)",
     "targets filter Crm.default_provider == :frontpad", "Provider change removes future target",
     "Partial Frontpad catalog refresh must preserve previous snapshot/issue state until next result"},
  "poller:Delivest.Integrations.Crm.SilencePoller" =>
    {"No provider call; finds stale sent Frontpad orders and writes CRM alert (crm/silence_poller.ex:29-68)",
     "targets filter Crm.default_provider == :frontpad; order status/sent alert query",
     "Provider change removes future target",
     "Alert is persisted diagnostic state; accepted orders remain separate provider obligations"},
  "poller:Delivest.Integrations.Rkeeper.Poller" =>
    {"No direct provider call; enqueues Rkeeper.PollWorker for active order IDs (rkeeper/poller.ex:20-43)",
     "targets = Rkeeper.active_branches; active_order_ids per branch",
     "Inactive branch removes future target but queued PollWorker remains",
     "Already sent orders still require status reconciliation by child PollWorker"},
  "poller:Delivest.Integrations.YandexEda.BusyPoller" =>
    {"Yandex Eda busy-state PushApi request",
     "poll checks PushApi.configured? per shared/branch settings",
     "Unconfigured branch skips external call",
     "Existing aggregator busy state can persist remotely until explicitly changed"},
  "poller:Delivest.Integrations.AtolOnline.KktPoller" =>
    {"Atol KKT info API", "targets select own fiscal mode/non-sandbox branch",
     "Mode change removes future target",
     "Pending fiscal receipts remain independent obligations"},
  "poller:Delivest.Integrations.Dadata.Poller" =>
    {"Dadata account/balance API", "poll checks Dadata.active?/0",
     "Disabled settings skip external call",
     "No business transaction in poll; cached health may become stale"},
  "poller:Delivest.Integrations.Yookassa.Reconciliation" =>
    {"Yookassa list_payments API", "targets only when Yookassa.configured?/0",
     "Missing config removes future target; existing reconciliation job may retry",
     "Pending payment/refund outcome must reconcile by provider ID"},
  "poller:Delivest.Integrations.YandexRating.Poller" =>
    {"No call currently: targets returns [] and poll stub", "targets=[]",
     "No jobs emitted by current targets",
     "No in-flight provider work from this poller implementation"}
}
