# Run only against an explicitly named disposable clone:
#   MIX_ENV=dev DEV_DATABASE=delivest_rf03_bench_<name> mix run --no-start scripts/rf03_statistics_benchmark.exs
database = System.get_env("DEV_DATABASE", "")

unless System.get_env("MIX_ENV") == "dev" and Mix.env() == :dev and
         String.starts_with?(database, "delivest_rf03_bench_") do
  raise "RF03 benchmark requires MIX_ENV=dev and DEV_DATABASE=delivest_rf03_bench_<name>"
end

alias Delivest.{Analytics, Identity, LocalTime, Repo}
alias Delivest.Analytics.{Overview, SalesCache}
Logger.configure(level: :error)

Application.put_env(
  :delivest,
  Oban,
  Application.fetch_env!(:delivest, Oban)
  |> Keyword.merge(testing: :manual, queues: false, plugins: false)
)

Application.put_env(
  :delivest,
  DelivestWeb.Endpoint,
  Application.fetch_env!(:delivest, DelivestWeb.Endpoint)
  |> Keyword.merge(server: false, watchers: [])
)

{:ok, _} = Application.ensure_all_started(:delivest)

staff =
  Repo.get_by!(Delivest.Identity.Staff, login: "demo_admin") |> Repo.preload([:role, :branches])

branches = Identity.list_branch_for_staff(staff)
branch = hd(branches)
ids = Enum.map(branches, & &1.id)
today = LocalTime.today()

:telemetry.attach(
  "rf03-measure",
  [:delivest, :repo, :query],
  fn _, _, _, _ ->
    if Process.get(:rf03_measuring),
      do: Process.put(:rf03_sql_count, Process.get(:rf03_sql_count, 0) + 1)
  end,
  nil
)

old = fn scope, period ->
  Analytics.summary(scope, period)
  Analytics.daily(scope, period)
  Analytics.hourly(scope, period)
  Analytics.breakdown(scope, period, :fulfillment_type)
  Analytics.breakdown(scope, period, :payment_method)
end

measure = fn label, f, cold ->
  rows =
    for _ <- 1..30 do
      if cold do
        for cache <- [:branch_cache, :franchise_cache], do: Cachex.clear(cache)
        Process.delete({SalesCache, :screen})
      end

      Process.put(:rf03_sql_count, 0)
      Process.put(:rf03_measuring, true)
      {us, result} = :timer.tc(f)
      Process.put(:rf03_measuring, false)
      if match?({:error, _}, result), do: raise("failed #{label}: #{inspect(result)}")
      {Process.get(:rf03_sql_count), us / 1000}
    end

  times = rows |> Enum.map(&elem(&1, 1)) |> Enum.sort()
  sqls = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

  out = %{
    label: label,
    samples: 30,
    sql: sqls,
    p50_ms: Enum.at(times, 14),
    p95_ms: Enum.at(times, 28)
  }

  IO.puts("RF03_RESULT " <> Jason.encode!(out))
  out
end

period = {Date.add(today, -365), today}
{:ok, first} = Overview.read(staff, :network, period)
IO.puts("RF03_FIRST_PUBLICATION " <> inspect(first.state))
# Rebuild only this disposable clone, never the person's running demo database.
rebuild = fn loop ->
  if SalesCache.rebuild_batch() > 0, do: loop.(loop), else: :ok
end

rebuild.(rebuild)

for {span, days} <- [{"7d", 7}, {"366d", 366}],
    {scope_label, old_scope, new_scope} <- [
      {"branch", branch.id, {:branch, branch.id}},
      {"network", ids, :network}
    ],
    {cache_label, cold} <- [{"warm", false}, {"cold_process_cache", true}] do
  period = {Date.add(today, -(days - 1)), today}
  measure.("old/#{scope_label}/#{span}/#{cache_label}", fn -> old.(old_scope, period) end, cold)

  measure.(
    "new/#{scope_label}/#{span}/#{cache_label}",
    fn -> Overview.read(staff, new_scope, period) end,
    cold
  )
end

period = {Date.add(today, -29), today}

Repo.query!(
  "UPDATE sales_daily_rollups SET dirty=true,revision=revision+1 WHERE day BETWEEN $1 AND $2",
  [elem(period, 0), Date.add(today, -1)]
)

background = Task.async(fn -> rebuild.(rebuild) end)

product =
  Repo.insert!(%Delivest.Net.Product{name: "RF03 benchmark", price: 10_000, is_active: true})

{:ok, _} = Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
Cachex.clear(:menu_cache)
product = product.id

checkout =
  Task.async(fn ->
    Enum.map(1..30, fn n ->
      {:ok, cart} =
        Delivest.Oms.Carts.create_cart(%{
          session_id: "rf03-bench-#{System.unique_integer([:positive])}-#{n}",
          branch_id: branch.id
        })

      {:ok, _, _} = Delivest.Oms.Carts.add_item(cart.id, product, 1)

      Delivest.Oms.Orders.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })
    end)
  end)

measure.(
  "new/network/30d/concurrent_checkout_and_rebuild",
  fn -> Overview.read(staff, :network, period) end,
  false
)

results = Task.await(checkout, 120_000)
Task.await(background, 120_000)

IO.puts(
  "RF03_CHECKOUT " <>
    Jason.encode!(%{
      attempted: length(results),
      succeeded: Enum.count(results, &match?({:ok, _}, &1))
    })
)
