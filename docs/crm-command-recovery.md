# CRM command ledger recovery

The release image contains `bin/delivest` (Dockerfile.server runs `mix release`);
it does not include Mix. These steps are for an operator, after an isolated
restore drill and backup. Do not run them on production during development.

## Coordinated rollout

Stop old server workers and all writers before applying migration 21. The
migration backfills existing `Delivest.Integrations.Crm.CommandWorker` Oban jobs
in job-ID order. Completed jobs become `succeeded`; available, scheduled and
retryable jobs become `pending`; executing, cancelled and discarded jobs are
conservatively `unknown`. The old job arguments remain supported through
the saved Oban job ID. An untracked old job is cancelled without a remote
call. Check `crm_commands` before starting the new workers.

The new worker commits a short per-order/provider claim before the remote
call. It does not hold a database transaction while calling the provider.
A process death after claim leaves `running`; the next attempt marks it
`unknown` and does not call the provider again. This provides local
serialization and prevents blind resend, not exactly-once remote delivery.
Provider response/timeout semantics still require verification with the
provider. Later commands for the same order/provider wait behind pending,
running, failed or unknown commands.

## Inspect and resolve

The bounded list omits CRM arguments and customer data:

```bash
MIX_ENV=prod mix delivest.crm_commands list --limit 100
MIX_ENV=prod mix delivest.crm_commands confirmed-effect --id 123 --actor STAFF_UUID --reason "verified in provider"
MIX_ENV=prod mix delivest.crm_commands skip --id 123 --actor STAFF_UUID --reason "operator decision"
MIX_ENV=prod mix delivest.crm_commands retry --id 123 --actor STAFF_UUID --reason "provider confirms absent" --confirmed-absent
```

`retry` is allowed only after explicit confirmation that the provider did
not apply the effect. The actor must be an active admin; reason is mandatory.
An active Oban job or claim blocks manual changes. Decisions are audited.
`confirmed-effect` and `skip` resolve an unknown/failed command and unblock
later commands; confirm the external order state first.

In the release image, call the same public API on a running node instead of
`mix`:

```bash
bin/delivest rpc 'Delivest.Integrations.Crm.Commands.list(100) |> IO.inspect()'
bin/delivest rpc 'Delivest.Integrations.Crm.Commands.resolve(123, "STAFF_UUID", "provider confirms absent", :retry, true) |> IO.inspect()'
```

Run the RPC on the release node with its normal environment. Record command
ID, provider observation, actor, reason and audit result outside the command
arguments. Do not send remote updates manually while an active claim exists.
