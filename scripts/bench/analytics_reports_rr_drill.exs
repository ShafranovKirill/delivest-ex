if Mix.env() != :test or System.get_env("TEST_DB_HOST") != "127.0.0.1" or
     not String.starts_with?(System.get_env("MIX_TEST_PARTITION") || "", "analyticsf04rr") do
  raise "run only against an isolated local analyticsf04rr test database"
end

repo_config = Application.fetch_env!(:delivest, Delivest.Repo)

Application.put_env(
  :delivest,
  Delivest.Repo,
  Keyword.put(repo_config, :pool, DBConnection.ConnectionPool)
)

{:ok, _} = Application.ensure_all_started(:delivest)

alias Delivest.{Analytics.Reports, Background, Features, Repo}

suffix = System.unique_integer([:positive])

branch =
  Delivest.Factory.insert(:branch,
    is_active: true,
    name: "RR branch #{suffix}",
    code: "RR#{suffix}",
    slug: "rr-#{suffix}"
  )

{:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "host")
{:ok, _} = Features.configure("analytics_extended", {:branch, branch.id}, true, actor: "host")
order = Delivest.OrderFixtures.order_fixture(branch.id, price: 1_234)
day = Delivest.LocalTime.today(Delivest.LocalTime.timezone(branch.id))

{:ok, writer} =
  Postgrex.start_link(
    hostname: "127.0.0.1",
    username: "postgres",
    password: "postgres",
    database: "delivest_test" <> System.fetch_env!("MIX_TEST_PARTITION")
  )

parent = self()
handler = "reports-rr-drill-#{System.unique_integer([:positive])}"

:ok =
  :telemetry.attach(
    handler,
    [:delivest, :analytics, :reports, :staged],
    fn _, _, metadata, _ ->
      if metadata.feature == "analytics_extended" and metadata.branch_id == branch.id do
        send(parent, {:staged, metadata.revision})

        Postgrex.query!(
          writer,
          "UPDATE orders SET status='completed',updated_at=timezone('UTC',now()) WHERE id=$1 AND status='created'",
          [Ecto.UUID.dump!(order.id)]
        )
      end
    end,
    nil
  )

started = System.monotonic_time(:millisecond)
{:ok, :queued} = Background.run_now("analytics.extended", {:branch, branch.id}, new_work: true)
{:ok, count} = Background.dispatch_due()
true = count >= 1
%{success: success} = Oban.drain_queue(queue: :background, with_safety: false)
true = success >= 1

{:staged, first} =
  receive do
    message -> message
  after
    5_000 -> raise "first stage missing"
  end

{:ok, :queued} = Background.run_now("analytics.extended", {:branch, branch.id}, new_work: true)
{:ok, next_count} = Background.dispatch_due()
true = next_count >= 1
%{success: next_success} = Oban.drain_queue(queue: :background, with_safety: false)
true = next_success >= 1
elapsed = System.monotonic_time(:millisecond) - started

{:staged, second} =
  receive do
    message -> message
  after
    5_000 -> raise "second stage missing"
  end

true = second > first

[[state_revision, published_revision]] =
  Repo.query!(
    "SELECT s.revision,p.revision FROM analytics_report_states s JOIN analytics_report_snapshots p ON p.id=s.snapshot_id WHERE s.feature='analytics_extended' AND s.branch_id=$1::text::uuid AND s.day=$2",
    [branch.id, day]
  ).rows

true = state_revision == published_revision

[[0], [1_234]] =
  Repo.query!(
    "SELECT COALESCE(sum((r.counts->>'revenue')::bigint),0)::bigint FROM analytics_report_snapshots p JOIN analytics_report_rows r ON r.snapshot_id=p.id WHERE p.feature='analytics_extended' AND p.branch_id=$1::text::uuid GROUP BY p.revision ORDER BY p.revision",
    [branch.id]
  ).rows

staff =
  Delivest.Factory.insert(:staff,
    login: "rr_staff_#{suffix}",
    role:
      Delivest.Factory.insert(:role, name: "RR role #{suffix}", permissions: ["statistics.read"])
  )

Delivest.Factory.insert(:staff_branch, staff: staff, branch: branch)

{:ok, %{totals: %{"revenue" => 1_234}, state: :partial, partial_days: 1}} =
  Reports.read(
    Repo.preload(staff, [:role, :branches]),
    {:branch, branch.id},
    {day, day},
    "channels"
  )

:telemetry.detach(handler)
GenServer.stop(writer)
true = elapsed < 120_000
IO.puts("RR independent-connection correction drill passed in #{elapsed} ms")
