# Event delivery recovery

The outbox stores one `domain_events.sequence` per aggregate. A transaction allocates the next number through `event_sequences` and inserts the event, its delivery rows, and Oban jobs. The sequence counter serializes concurrent writers for the same aggregate. Subscriber delivery uses a transaction-scoped advisory lock per aggregate and subscriber; an unresolved earlier delivery snoozes later jobs. A handler's database writes and the delivered acknowledgement commit together. A discarded or cancelled job leaves its delivery pending, so later events remain blocked until recovery.

Run `mix delivest.events list` to show up to 100 pending deliveries with their age, aggregate, sequence, and recent job states. For a failed or pruned job, use:

```
mix delivest.events retry --event UUID --subscriber KEY --actor STAFF_UUID --reason 'incident ticket and cause'
mix delivest.events resolve --event UUID --subscriber KEY --actor STAFF_UUID --reason 'why this event can be skipped'
```

The actor must be an active staff member with the admin role. Both commands require a nonempty reason and write a durable audit event in the same transaction. They refuse active or completed jobs. `retry` inserts a new delivery job, including when the previous job was pruned. `resolve` explicitly skips the delivery and permits later events for that subscriber to proceed. Keep the events worker running while inspecting; stop new execution of the specific delivery before retrying or resolving it.

During migration, stop old application writers and workers, apply the migration, and then start the new version. The schema requires sequence values immediately. Existing events receive sequence numbers ordered by `(inserted_at, id)`; the original order of events with identical timestamps cannot be reconstructed. Only event/subscriber pairs found in retained Oban jobs get backfilled delivery rows. Completed jobs become delivered; unfinished, cancelled, and discarded jobs remain pending. Pruned historical jobs are not requeued. Old job arguments continue through the same delivery ledger, creating a missing row under the aggregate/subscriber lock.

Database effects and acknowledgements are atomic. External HTTP calls are not exactly once: a process may die after a remote payment call and before the database commit. Payment calls use stable idempotency keys, and the payments queue runs at concurrency 2 to cap occupied database connections. A payment job has a 180 second hard timeout; a transaction may be retried if several provider calls exceed that budget. The ordinary events queue keeps concurrency 10 and a 15 second transaction budget. Delivery order here governs subscriber acknowledgement; any downstream jobs enqueued by subscribers have their own execution order.
