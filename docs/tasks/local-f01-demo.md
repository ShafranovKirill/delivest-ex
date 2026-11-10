# Local F01 demo

This is an isolated, synthetic development dataset. The example uses PostgreSQL database `delivest_f01_demo_20261110`; the script accepts only names beginning with `delivest_f01_demo_`, a loopback database host, the dev Mix environment, and server port 4000. It seeds an empty database and can finish its policy/report warmup after a later restart. An incomplete base dataset requires recreating that dedicated database before retrying.

Start PostgreSQL and local S3, then from `server/`:

```sh
export MIX_ENV=dev DEV_DATABASE=delivest_f01_demo_20261110 DEV_EXTERNAL_HOST=127.0.0.1 DEV_DATABASE_PORT=5432
export DEFAULT_LOCALE=ru PORT=4000 CLIENT_ORIGIN=http://localhost:3000
mix ecto.create
mix ecto.migrate
mix run --no-start scripts/local_f01_demo.exs
```

Start the client from `client/` with `VITE_API_BASE_URL=http://localhost:4000 pnpm dev --host 127.0.0.1 --port 3000 --strictPort`. Staff login: `demo_admin` / `DemoPassword123!`. Customer phone examples: `+79990000001` (unused return offers and 500 bonus points), `+79990000002` (completed return order), and `+79990000181` (new guest). Enter the ten digits after `+7` in the phone field, e.g. `9990000001`. Dev confirms the number automatically after a short wait; no call is sent.

Open `http://localhost:4000/staff/b/demo-center/statistics` for sales, `/staff/segments` for groups, and `/staff/marketing` for policies. In the policy “Возвращение — 500 бонусов”, click “Показать” to view the warmed report with return orders. The promotion policy has no synthetic promo redemptions. The client menu is `http://localhost:3000/demo-center`; channel settings are at `/demo-center/notification-channels`.

The seed creates three Moscow branches, ten menu products, 185 synthetic customers, 1,800 historical orders across the previous 90 days, paid cash records, cancellations, a few open orders and manual cash refunds. After genuine F01 issues it adds 19 completed return orders. It creates six segments and four marketing policies, with two activated policies after actual background previews. Reports are requested through the F01 report service. The shared bounded background queue computes previews, evaluations, and report snapshots before the launcher prints `Demo ready`.

The backend launcher blocks outbound HTTP and Push through local 503 responses. SMS has no provider; marketing consent remains false. Cash is the only seeded payment record, with no remote payment or fiscalization. Fiscalization is off, online payments are off, and no CRM or channel credentials are configured. “Sent” or “delivered” provider statistics are not synthetic fixtures. Orders, payments, customers, and menu data are synthetic and only for local exploration.
