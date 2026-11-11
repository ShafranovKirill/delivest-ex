# Run only against a fresh isolated test partition:
# MIX_ENV=test MIX_TEST_PARTITION=segmentsbench20261110 TEST_DB_HOST=127.0.0.1 mix ecto.create
# MIX_ENV=test MIX_TEST_PARTITION=segmentsbench20261110 TEST_DB_HOST=127.0.0.1 mix ecto.migrate
# MIX_ENV=test MIX_TEST_PARTITION=segmentsbench20261110 TEST_DB_HOST=127.0.0.1 mix run scripts/bench/segments.exs

alias Delivest.{Features, Repo, Segments}
alias Delivest.Background.Schedule
alias Delivest.Identity.Client
alias Delivest.Oms.Order
import Ecto.Query
import Delivest.Factory

partition = System.get_env("MIX_TEST_PARTITION", "")

unless Mix.env() == :test and String.starts_with?(partition, "segmentsbench") and
         String.contains?(Repo.config()[:database] || "", "test") do
  raise "segments benchmark requires an isolated segmentsbench test database"
end

Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

unless Repo.aggregate(Client, :count) == 0 and Repo.aggregate(Order, :count) == 0 do
  raise "segments benchmark requires an empty test database"
end

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
schema_now = DateTime.utc_now() |> DateTime.truncate(:second)
branches = for _ <- 1..5, do: insert(:branch, is_active: true)

{:ok, _} = Features.configure("segments", :franchise, true, actor: "synthetic-benchmark")

Enum.each(branches, fn branch ->
  {:ok, _} =
    Features.configure("segments", {:branch, branch.id}, true, actor: "synthetic-benchmark")
end)

client_ids = for _ <- 1..1000, do: Ecto.UUID.generate()

client_ids
|> Enum.with_index(1)
|> Enum.chunk_every(250)
|> Enum.each(fn chunk ->
  Repo.insert_all(
    Client,
    Enum.map(chunk, fn {id, i} ->
      %{
        id: id,
        name: "Synthetic #{i}",
        phone: "+7900#{String.pad_leading(to_string(i), 7, "0")}",
        status: :active,
        inserted_at: schema_now,
        updated_at: schema_now
      }
    end)
  )
end)

order_ids = for _ <- 1..5000, do: Ecto.UUID.generate()
cart_ids = for _ <- 1..5000, do: Ecto.UUID.generate()

1..5000
|> Enum.chunk_every(250)
|> Enum.each(fn chunk ->
  Repo.insert_all(
    "carts",
    Enum.map(chunk, fn i ->
      branch = Enum.at(branches, div(i - 1, 1000))

      %{
        id: Ecto.UUID.dump!(Enum.at(cart_ids, i - 1)),
        branch_id: Ecto.UUID.dump!(branch.id),
        inserted_at: now,
        updated_at: now
      }
    end)
  )

  Repo.insert_all(
    "orders",
    Enum.map(chunk, fn i ->
      branch = Enum.at(branches, div(i - 1, 1000))

      %{
        id: Ecto.UUID.dump!(Enum.at(order_ids, i - 1)),
        number: "BM-#{i}",
        branch_id: Ecto.UUID.dump!(branch.id),
        cart_id: Ecto.UUID.dump!(Enum.at(cart_ids, i - 1)),
        client_id: Ecto.UUID.dump!(Enum.at(client_ids, rem(i - 1, 1000))),
        status: "completed",
        fulfillment_type: "pickup",
        payment_method: "cash",
        source: "app",
        total_amount: 10_000 + rem(i, 5_000),
        business_date: Date.utc_today(),
        daily_number: rem(i - 1, 1000) + 1,
        inserted_at: now,
        updated_at: now
      }
    end)
  )
end)

admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

rules = %{
  "version" => 1,
  "match" => "all",
  "conditions" => [
    %{"metric" => "order_count", "op" => "gte", "value" => 1}
  ]
}

{:ok, _group} =
  Segments.create(admin, %{
    name: "Synthetic purchasers",
    kind: :dynamic,
    scope: :franchise,
    rules: rules
  })

Enum.each(Enum.take(branches, 3), fn branch ->
  {:ok, _} =
    Segments.create(
      admin,
      %{name: "Synthetic branch #{branch.code}", kind: :dynamic, scope: :branches, rules: rules},
      [branch.id]
    )
end)

{:ok, token} = Features.snapshot("segments", :franchise)
schedule = Repo.one!(Schedule)

Repo.update_all(from(s in Schedule, where: s.id == ^schedule.id),
  set: [running: true, current_job_id: 999]
)

context = %{
  feature: "segments",
  scope: :franchise,
  generation: token,
  schedule_id: schedule.id,
  job_id: 999
}

{:ok, counter} = Agent.start_link(fn -> %{count: 0, metrics_query: nil, params: nil} end)

:telemetry.attach(
  "segments-benchmark-orders",
  [:delivest, :repo, :query],
  fn _event, _measurements, metadata, pid ->
    query = Map.get(metadata, :query, "")

    if String.contains?(query, "orders") and
         String.starts_with?(String.trim_leading(query), "SELECT") do
      Agent.update(pid, fn state ->
        state = %{state | count: state.count + 1}

        if state.metrics_query == nil and String.contains?(query, "order_refunds"),
          do: %{state | metrics_query: query, params: Map.get(metadata, :params, [])},
          else: state
      end)
    end
  end,
  counter
)

measure = fn label ->
  Agent.update(counter, &%{&1 | count: 0})
  {microseconds, result} = :timer.tc(fn -> Segments.Refresh.perform(:franchise, context) end)

  IO.puts(
    "#{label}: #{Float.round(microseconds / 1_000_000, 3)} s, orders SELECTs=#{Agent.get(counter, & &1.count)}, result=#{inspect(result)}"
  )

  if result != :ok, do: raise("benchmark refresh failed")
end

measure.("baseline")
measure.("unchanged")
Repo.update_all(from(o in Order, where: o.id == ^hd(order_ids)), set: [total_amount: 22_000])
measure.("one changed client")

cpu =
  File.read!("/proc/cpuinfo")
  |> String.split("\n")
  |> Enum.find(&String.starts_with?(&1, "model name"))

[[pg_version]] = Repo.query!("SELECT current_setting('server_version')").rows

IO.puts(
  "Environment: Elixir #{System.version()}, PostgreSQL #{pg_version}, #{cpu || "CPU unknown"}"
)

%{metrics_query: query, params: params} = Agent.get(counter, & &1)
if query == nil, do: raise("metrics query telemetry not captured")
plan = Repo.query!("EXPLAIN (ANALYZE, BUFFERS) " <> query, params).rows
IO.puts("EXPLAIN actual net-refund metrics query, first 250 clients / one branch:")
Enum.each(plan, fn [line] -> IO.puts(String.slice(line, 0, 220)) end)

:telemetry.detach("segments-benchmark-orders")
