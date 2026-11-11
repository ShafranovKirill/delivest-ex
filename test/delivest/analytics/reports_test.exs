defmodule Delivest.Analytics.ReportsTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  @moduletag :repeatable_read

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Analytics.Reports, Background, Features, Funnel, LocalTime, Payments, Repo}
  alias Delivest.Analytics.Reports.{Prune, Query}
  alias Delivest.Advertising.{Click, Links}
  alias Delivest.Oms.{Carts, Orders}

  setup do
    branch = insert(:branch, is_active: true)
    analyst = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: analyst, branch: branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    %{
      branch: branch,
      analyst: Repo.preload(analyst, [:role, :branches]),
      admin: Repo.preload(admin, [:role, :branches])
    }
  end

  defp today(branch), do: LocalTime.today(LocalTime.timezone(branch.id))

  defp enable(feature, branch) do
    assert {:ok, _} = Features.configure(feature, :franchise, true, actor: "host")
    assert {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "host")
  end

  defp collected_before(feature, branch, day) do
    before_day =
      day
      |> LocalTime.start_of_day_utc(LocalTime.timezone(branch.id))
      |> DateTime.add(-1, :second)

    Repo.query!(
      "UPDATE feature_audits SET inserted_at=$1 WHERE feature=$2 AND scope_key IN ('franchise',$3)",
      [before_day, feature, "branch:" <> branch.id]
    )
  end

  defp run_report(kind, branch) do
    assert {:ok, :queued} = Background.run_now(kind, {:branch, branch.id}, new_work: true)
    assert {:ok, count} = Background.dispatch_due()
    assert count >= 1
    assert %{success: success} = Oban.drain_queue(queue: :background, with_safety: false)
    assert success >= 1
  end

  test "disabled extended analytics writes no identity or report and refuses reads", ctx do
    order = order_fixture(ctx.branch.id)

    assert {:error, :forbidden} =
             Reports.read(
               ctx.analyst,
               {:branch, ctx.branch.id},
               {today(ctx.branch), today(ctx.branch)},
               "channels"
             )

    assert Repo.query!(
             "SELECT count(*) FROM analytics_order_identities WHERE order_id=$1::text::uuid",
             [order.id]
           ).rows == [[0]]

    assert Repo.query!(
             "SELECT count(*) FROM analytics_report_states WHERE branch_id=$1::text::uuid",
             [ctx.branch.id]
           ).rows == [[0]]

    assert {:error, :disabled} =
             Background.run_now("analytics.extended", {:branch, ctx.branch.id})
  end

  test "same-day branch off and on keeps observations but marks collection incomplete", ctx do
    enable("analytics_extended", ctx.branch)
    day = today(ctx.branch)
    collected_before("analytics_extended", ctx.branch, day)

    first = order_fixture(ctx.branch.id, price: 100)
    Repo.update!(Ecto.Changeset.change(first, status: :completed))

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, ctx.branch.id}, false,
               actor: "host"
             )

    gap = order_fixture(ctx.branch.id, price: 200)
    Repo.update!(Ecto.Changeset.change(gap, status: :completed))

    assert {:ok, _} =
             Features.configure("analytics_extended", {:branch, ctx.branch.id}, true,
               actor: "host"
             )

    last = order_fixture(ctx.branch.id, price: 300)
    Repo.update!(Ecto.Changeset.change(last, status: :completed))
    run_report("analytics.extended", ctx.branch)

    assert {:ok,
            %{
              state: :partial,
              partial_days: 1,
              covered_days: 0,
              totals: %{"revenue" => 400, "completed" => 2}
            }} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "channels")

    assert Repo.query!(
             "SELECT count(*) FROM analytics_order_identities WHERE order_id=$1::text::uuid",
             [gap.id]
           ).rows == [[0]]
  end

  test "same-day franchise off and on marks the branch day incomplete", ctx do
    enable("analytics_extended", ctx.branch)
    day = today(ctx.branch)
    collected_before("analytics_extended", ctx.branch, day)

    assert {:ok, _} = Features.configure("analytics_extended", :franchise, false, actor: "host")
    gap = order_fixture(ctx.branch.id, price: 200)
    Repo.update!(Ecto.Changeset.change(gap, status: :completed))
    assert {:ok, _} = Features.configure("analytics_extended", :franchise, true, actor: "host")
    after_gap = order_fixture(ctx.branch.id, price: 300)
    Repo.update!(Ecto.Changeset.change(after_gap, status: :completed))
    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{state: :partial, partial_days: 1, totals: %{"revenue" => 300}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "channels")
  end

  test "manual rebuild of a fully disabled historical day cannot claim complete zero", ctx do
    enable("analytics_extended", ctx.branch)
    old_day = Date.add(today(ctx.branch), -1)

    assert {:ok, :queued} =
             Reports.request_rebuild(
               ctx.admin,
               "analytics_extended",
               ctx.branch.id,
               {old_day, old_day}
             )

    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{state: :partial, partial_days: 1, covered_days: 0, totals: %{"revenue" => 0}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {old_day, old_day}, "channels")
  end

  test "manual extended rebuild publishes an available order beyond raw retention", ctx do
    enable("analytics_extended", ctx.branch)
    old_day = Date.add(today(ctx.branch), -100)
    order = order_fixture(ctx.branch.id, price: 987)
    Repo.update!(Ecto.Changeset.change(order, status: :completed))
    old_time = LocalTime.start_of_day_utc(old_day, LocalTime.timezone(ctx.branch.id))

    Repo.query!(
      "UPDATE orders SET inserted_at=$1 WHERE id=$2::text::uuid",
      [DateTime.add(old_time, 3_600, :second), order.id]
    )

    assert {:ok, :queued} =
             Reports.request_rebuild(
               ctx.admin,
               "analytics_extended",
               ctx.branch.id,
               {old_day, old_day}
             )

    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{state: :partial, totals: %{"completed" => 1, "revenue" => 987}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {old_day, old_day}, "channels")
  end

  test "enabling exactly at local midnight covers the day, later activation does not", ctx do
    enable("analytics_extended", ctx.branch)
    day = today(ctx.branch)
    midnight = LocalTime.start_of_day_utc(day, LocalTime.timezone(ctx.branch.id))

    Repo.query!(
      "UPDATE feature_audits SET inserted_at=$1 WHERE feature='analytics_extended' AND scope_key IN ('franchise',$2)",
      [midnight, "branch:" <> ctx.branch.id]
    )

    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{state: :empty, partial_days: 0, covered_days: 1}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "channels")

    Repo.query!(
      "UPDATE feature_audits SET inserted_at=$1 WHERE feature='analytics_extended' AND scope_key=$2",
      [DateTime.add(midnight, 1, :microsecond), "branch:" <> ctx.branch.id]
    )

    assert {:ok, %{state: :partial, partial_days: 1, covered_days: 0}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "channels")
  end

  test "published completed revenue is corrected without double counting", ctx do
    enable("analytics_extended", ctx.branch)
    order = order_fixture(ctx.branch.id, price: 12_345)

    assert Repo.query!(
             "SELECT owner_kind FROM analytics_order_identities WHERE order_id=$1::text::uuid",
             [order.id]
           ).rows == [["unknown"]]

    Repo.update!(Ecto.Changeset.change(order, status: :completed))
    run_report("analytics.extended", ctx.branch)
    period = {today(ctx.branch), today(ctx.branch)}

    assert {:ok, %{rows: [%{counts: %{"completed" => 1, "revenue" => 12_345}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")

    assert {:ok, %{verified_buyers: 0}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "customers")

    Repo.update!(Ecto.Changeset.change(Repo.reload!(order), status: :created))
    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{rows: [%{counts: %{"completed" => 0, "revenue" => 0}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")
  end

  test "a correction arriving after staging publishes a coherent version then converges", ctx do
    enable("analytics_extended", ctx.branch)
    order = order_fixture(ctx.branch.id, price: 1_234)
    handler = "reports-dirty-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :analytics, :reports, :staged],
        fn _event, _measurements, metadata, _config ->
          if metadata.feature == "analytics_extended" and metadata.branch_id == ctx.branch.id do
            send(parent, {:staged_revision, metadata.revision})
            current = Repo.reload!(order)

            if current.status == :created,
              do: Repo.update!(Ecto.Changeset.change(current, status: :completed))
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    run_report("analytics.extended", ctx.branch)

    assert_receive {:staged_revision, first_revision}
    run_report("analytics.extended", ctx.branch)
    assert_receive {:staged_revision, second_revision}
    assert second_revision > first_revision

    assert [[state_revision, published_revision, 2]] =
             Repo.query!(
               "SELECT s.revision,p.revision,(SELECT count(*) FROM analytics_report_snapshots x WHERE x.feature=s.feature AND x.branch_id=s.branch_id AND x.day=s.day) FROM analytics_report_states s JOIN analytics_report_snapshots p ON p.id=s.snapshot_id WHERE s.feature='analytics_extended' AND s.branch_id=$1::text::uuid AND s.day=$2",
               [ctx.branch.id, today(ctx.branch)]
             ).rows

    assert state_revision == published_revision

    assert [[^first_revision, 0], [^second_revision, 1_234]] =
             Repo.query!(
               "SELECT p.revision,COALESCE(sum((r.counts->>'revenue')::bigint),0)::bigint FROM analytics_report_snapshots p JOIN analytics_report_rows r ON r.snapshot_id=p.id WHERE p.feature='analytics_extended' AND p.branch_id=$1::text::uuid AND p.day=$2 GROUP BY p.revision ORDER BY p.revision",
               [ctx.branch.id, today(ctx.branch)]
             ).rows

    assert {:ok, %{totals: %{"revenue" => 1_234}, state: :partial, partial_days: 1}} =
             Reports.read(
               ctx.analyst,
               {:branch, ctx.branch.id},
               {today(ctx.branch), today(ctx.branch)},
               "channels"
             )
  end

  test "an older staged run cannot replace a newer published revision", ctx do
    enable("analytics_extended", ctx.branch)
    order_fixture(ctx.branch.id, price: 700)
    handler = "reports-newer-#{System.unique_integer([:positive])}"
    newer_id = Ecto.UUID.generate()

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :analytics, :reports, :staged],
        fn _event, _measurements, metadata, _config ->
          if metadata.feature == "analytics_extended" and metadata.branch_id == ctx.branch.id do
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

            Repo.query!(
              "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,'analytics_extended',$2::text::uuid,$3,$4,1,1,$5,$5)",
              [newer_id, ctx.branch.id, metadata.day, metadata.revision + 1, now]
            )

            Repo.query!(
              "UPDATE analytics_report_states SET revision=$1,snapshot_id=$2::text::uuid,published_at=$3,source_asof=$3 WHERE feature='analytics_extended' AND branch_id=$4::text::uuid AND day=$5",
              [metadata.revision + 1, newer_id, now, ctx.branch.id, metadata.day]
            )
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    run_report("analytics.extended", ctx.branch)

    assert Repo.query!(
             "SELECT snapshot_id::text FROM analytics_report_states WHERE feature='analytics_extended' AND branch_id=$1::text::uuid AND day=$2",
             [ctx.branch.id, today(ctx.branch)]
           ).rows == [[newer_id]]

    assert Repo.query!(
             "SELECT count(*) FROM analytics_report_snapshots WHERE feature='analytics_extended' AND branch_id=$1::text::uuid AND day=$2",
             [ctx.branch.id, today(ctx.branch)]
           ).rows == [[1]]
  end

  test "a re-dirtied current day does not starve an older pending day", ctx do
    enable("analytics_extended", ctx.branch)
    today = today(ctx.branch)
    old_day = Date.add(today, -2)

    Repo.query!(
      "INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,1,timezone('UTC',now()),timezone('UTC',now()))",
      [ctx.branch.id, old_day]
    )

    handler = "reports-fairness-#{System.unique_integer([:positive])}"
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :analytics, :reports, :staged],
        fn _, _, metadata, _ ->
          if metadata.feature == "analytics_extended" and metadata.branch_id == ctx.branch.id and
               metadata.day == today and Agent.get_and_update(counter, &{&1, &1 + 1}) == 0 do
            Repo.query!(
              "UPDATE analytics_report_states SET revision=revision+1 WHERE feature='analytics_extended' AND branch_id=$1::text::uuid AND day=$2",
              [ctx.branch.id, today]
            )
          end
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler)
      if Process.alive?(counter), do: Agent.stop(counter)
    end)

    run_report("analytics.extended", ctx.branch)

    assert Repo.query!(
             "SELECT count(*) FROM analytics_report_states WHERE feature='analytics_extended' AND branch_id=$1::text::uuid AND day=$2 AND snapshot_id IS NOT NULL",
             [ctx.branch.id, old_day]
           ).rows == [[1]]
  end

  test "branch and network reads enforce permission and feature scope", ctx do
    other = insert(:branch)
    enable("analytics_franchise", ctx.branch)

    assert {:ok, _} =
             Features.configure("analytics_franchise", {:branch, other.id}, true, actor: "host")

    order = order_fixture(ctx.branch.id, price: 1_000)
    Repo.update!(Ecto.Changeset.change(order, status: :completed))
    run_report("analytics.extended", ctx.branch)

    period = {today(ctx.branch), today(ctx.branch)}
    assert {:error, :forbidden} = Reports.read(ctx.analyst, :franchise, period, "franchise")

    assert {:error, :forbidden} =
             Reports.read(ctx.analyst, {:branch, other.id}, period, "channels")

    assert {:ok, %{totals: %{"revenue" => 1_000}}} =
             Reports.read(ctx.admin, :franchise, period, "franchise")
  end

  test "manual rebuild is host admin only and never runs on read", ctx do
    enable("analytics_extended", ctx.branch)
    period = {today(ctx.branch), today(ctx.branch)}

    assert {:error, :forbidden} =
             Reports.request_rebuild(ctx.analyst, "analytics_extended", ctx.branch.id, period)

    assert {:ok, %{state: :not_collected}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")

    assert {:ok, :queued} =
             Reports.request_rebuild(ctx.admin, "analytics_extended", ctx.branch.id, period)
  end

  test "manual rebuild rejects future local days without creating work", ctx do
    enable("analytics_extended", ctx.branch)
    future = Date.add(today(ctx.branch), 1)

    assert {:error, :forbidden} =
             Reports.request_rebuild(
               ctx.admin,
               "analytics_extended",
               ctx.branch.id,
               {future, future}
             )

    assert Repo.query!(
             "SELECT count(*) FROM analytics_report_states WHERE feature='analytics_extended' AND branch_id=$1::text::uuid AND day=$2",
             [ctx.branch.id, future]
           ).rows == [[0]]

    assert Repo.query!(
             "SELECT count(*) FROM background_schedules WHERE kind='analytics.extended' AND scope_key=$1 AND rerun_requested",
             ["branch:" <> ctx.branch.id]
           ).rows == [[0]]

    expired = Date.shift(Date.utc_today(), month: -36) |> Date.add(-1)

    assert {:error, :forbidden} =
             Reports.request_rebuild(
               ctx.admin,
               "analytics_extended",
               ctx.branch.id,
               {expired, expired}
             )
  end

  test "raw expiry boundary preserves published funnel stages and link clicks", ctx do
    enable("analytics_funnel", ctx.branch)
    enable("analytics_links", ctx.branch)
    old_day = Date.add(today(ctx.branch), -90)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    link_id = Ecto.UUID.generate()

    for {feature, dimension, key, counts} <- [
          {"analytics_funnel", "stage", "visit", %{"sessions" => 7}},
          {"analytics_links", "link", link_id, %{"clicks" => 5}}
        ] do
      snapshot = Ecto.UUID.generate()

      Repo.query!(
        "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,$2,$3::text::uuid,$4,0,1,1,$5,$5)",
        [snapshot, feature, ctx.branch.id, old_day, now]
      )

      Repo.query!(
        "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ($1,$2::text::uuid,$3,1,$4::text::uuid,$5,$5,$5,$5)",
        [feature, ctx.branch.id, old_day, snapshot, now]
      )

      Repo.query!(
        "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) VALUES ($1::text::uuid,$2,$3,$4,$5::text::jsonb)",
        [
          snapshot,
          if(feature == "analytics_funnel", do: "funnel", else: "links"),
          dimension,
          key,
          Jason.encode!(counts)
        ]
      )
    end

    Repo.query!(
      "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) SELECT snapshot_id,'funnel','session_source','direct',$1::text::jsonb FROM analytics_report_states WHERE feature='analytics_funnel' AND branch_id=$2::text::uuid AND day=$3",
      [Jason.encode!(%{"sessions" => 7}), ctx.branch.id, old_day]
    )

    run_report("analytics.funnel", ctx.branch)
    run_report("analytics.links", ctx.branch)

    assert {:ok, %{rows: funnel_rows}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {old_day, old_day}, "funnel")

    assert Enum.find(funnel_rows, &(&1.dimension == "stage")).counts["sessions"] == 7
    assert Enum.find(funnel_rows, &(&1.dimension == "session_source")).counts["sessions"] == 7

    assert {:ok, %{rows: [%{counts: %{"clicks" => 5}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {old_day, old_day}, "sources")

    assert {:error, :forbidden} =
             Reports.request_rebuild(
               ctx.admin,
               "analytics_links",
               ctx.branch.id,
               {old_day, old_day}
             )
  end

  test "aggregate retention keeps exactly 36 calendar months", ctx do
    old_day = ~D[2023-11-10]
    kept_day = ~D[2023-11-11]

    for day <- [old_day, kept_day] do
      Repo.query!(
        "INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,0,timezone('UTC',now()),timezone('UTC',now()))",
        [ctx.branch.id, day]
      )
    end

    assert %{states: 1} = Prune.prune(~D[2026-11-11])

    assert Repo.query!(
             "SELECT day FROM analytics_report_states WHERE branch_id=$1::text::uuid",
             [ctx.branch.id]
           ).rows == [[kept_day]]
  end

  test "leap-day retention cutoff clamps to February 28", ctx do
    for day <- [~D[2021-02-27], ~D[2021-02-28]] do
      Repo.query!(
        "INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,0,timezone('UTC',now()),timezone('UTC',now()))",
        [ctx.branch.id, day]
      )
    end

    assert %{states: 1} = Prune.prune(~D[2024-02-29])

    assert Repo.query!(
             "SELECT day FROM analytics_report_states WHERE branch_id=$1::text::uuid",
             [ctx.branch.id]
           ).rows == [[~D[2021-02-28]]]
  end

  test "historic published data stays ready regardless of its publication age", ctx do
    enable("analytics_extended", ctx.branch)
    day = Date.add(today(ctx.branch), -30)
    collected_before("analytics_extended", ctx.branch, day)
    snapshot = Ecto.UUID.generate()
    old_asof = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:microsecond)

    Repo.query!(
      "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,'analytics_extended',$2::text::uuid,$3,0,1,1,$4,$4)",
      [snapshot, ctx.branch.id, day, old_asof]
    )

    Repo.query!(
      "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,0,$3::text::uuid,$4,$4,$4,$4)",
      [ctx.branch.id, day, snapshot, old_asof]
    )

    Repo.query!(
      "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) VALUES ($1::text::uuid,'extended','channel','web',$2::text::jsonb)",
      [snapshot, Jason.encode!(%{"created" => 1, "completed" => 1, "revenue" => 500})]
    )

    assert {:ok, %{state: :ready, totals: %{"revenue" => 500}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "channels")
  end

  test "current report freshness follows successful checks without new events", ctx do
    enable("analytics_funnel", ctx.branch)
    enable("analytics_extended", ctx.branch)
    collected_before("analytics_funnel", ctx.branch, today(ctx.branch))
    collected_before("analytics_extended", ctx.branch, today(ctx.branch))
    run_report("analytics.funnel", ctx.branch)
    run_report("analytics.extended", ctx.branch)
    day = today(ctx.branch)

    assert {:ok, %{state: :empty, last_checked_at: %DateTime{}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "funnel")

    for {kind, tab, hours, ready_age} <- [
          {"analytics.funnel", "funnel", "16 minutes", "14 minutes"},
          {"analytics.extended", "channels", "25 hours", "23 hours"}
        ] do
      Repo.query!(
        "UPDATE background_schedules SET last_success_at=timezone('UTC',now())-$1::text::interval WHERE kind=$2 AND scope_key=$3",
        [hours, kind, "branch:" <> ctx.branch.id]
      )

      assert {:ok, %{state: :stale}} =
               Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, tab)

      run_report(kind, ctx.branch)

      assert {:ok, %{state: :empty, last_checked_at: %DateTime{}}} =
               Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, tab)

      Repo.query!(
        "UPDATE background_schedules SET last_success_at=timezone('UTC',now())-$1::text::interval WHERE kind=$2 AND scope_key=$3",
        [ready_age, kind, "branch:" <> ctx.branch.id]
      )

      assert {:ok, %{state: :empty}} =
               Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, tab)
    end
  end

  test "published dimensions are aggregated and paged in SQL", ctx do
    day = today(ctx.branch)
    snapshot = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.query!(
      "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,'analytics_extended',$2::text::uuid,$3,0,1,1,$4,$4)",
      [snapshot, ctx.branch.id, day, now]
    )

    Repo.query!(
      "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,0,$3::text::uuid,$4,$4,$4,$4)",
      [ctx.branch.id, day, snapshot, now]
    )

    keys = for n <- 1..60, do: "source-#{String.pad_leading(Integer.to_string(n), 2, "0")}"

    Repo.query!(
      ~S"""
      INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts)
      SELECT $1::text::uuid,'extended','channel',k,
        '{"created":1,"completed":1,"revenue":100}'::jsonb FROM unnest($2::text[]) k
      """,
      [snapshot, keys]
    )

    first = Query.read("analytics_extended", [ctx.branch.id], day, day, "channels", %{}, 1)
    second = Query.read("analytics_extended", [ctx.branch.id], day, day, "channels", %{}, 2)

    assert first.total_rows == 60
    assert length(first.rows) == 50
    assert length(second.rows) == 10
    assert first.totals["revenue"] == 6_000
    assert second.rows |> hd() |> Map.fetch!(:key) == "source-51"
  end

  test "customer batches cover 510 verified buyers within one bounded refresh", ctx do
    enable("analytics_extended", ctx.branch)
    day = today(ctx.branch)

    Repo.query!(
      "INSERT INTO clients(id,phone,inserted_at,updated_at) SELECT md5($1||':client:'||n)::uuid,'+7999'||lpad(n::text,7,'0'),timezone('UTC',now()),timezone('UTC',now()) FROM generate_series(1,510) n",
      [ctx.branch.id]
    )

    Repo.query!(
      "INSERT INTO orders(id,number,branch_id,cart_id,status,fulfillment_type,payment_method,total_amount,inserted_at,updated_at,source,business_date,daily_number) SELECT md5($1||':order:'||n)::uuid,$1||'-load-'||n,$1::text::uuid,md5($1||':cart:'||n)::uuid,'completed','pickup','cash',100,timezone('UTC',now()),timezone('UTC',now()),'web',$2,n FROM generate_series(1,510) n",
      [ctx.branch.id, day]
    )

    Repo.query!(
      "INSERT INTO analytics_order_identities(order_id,verified_client_id,owner_kind,as_of_at,inserted_at) SELECT md5($1||':order:'||n)::uuid,md5($1||':client:'||n)::uuid,'client',timezone('UTC',now()),timezone('UTC',now()) FROM generate_series(1,510) n",
      [ctx.branch.id]
    )

    {:ok, queries} = Agent.start_link(fn -> 0 end)
    handler = "reports-query-count-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, _, _ -> Agent.update(queries, &(&1 + 1)) end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler)
      if Process.alive?(queries), do: Agent.stop(queries)
    end)

    started = System.monotonic_time(:millisecond)
    run_report("analytics.extended", ctx.branch)
    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed < 120_000
    assert Agent.get(queries, & &1) < 120

    assert {:ok, %{verified_buyers: 510, totals: %{"revenue" => 51_000}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "customers")
  end

  test "completed cash revenue follows a real succeeded refund on the creation day", ctx do
    enable("analytics_extended", ctx.branch)
    order = order_fixture(ctx.branch.id, price: 2_000)
    {:ok, completed} = Orders.advance_order(order, :completed, :system)
    run_report("analytics.extended", ctx.branch)
    period = {today(ctx.branch), today(ctx.branch)}

    assert {:ok, %{totals: %{"revenue" => 2_000}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")

    [payment] = Payments.list(completed.id)
    assert {:ok, %{status: :succeeded}} = Payments.refund(payment, 500)
    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{totals: %{"revenue" => 1_500}, rows: [%{counts: %{"refunded" => 500}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")
  end

  test "funnel separates session conversion, pending online payment, paid and cash", ctx do
    enable("analytics_funnel", ctx.branch)
    guest = Ecto.UUID.generate()

    assert {:ok, _} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => ctx.branch.id,
                 "event" => "visit",
                 "source_type" => "campaign",
                 "utm_source" => "unverified"
               },
               "guest:" <> guest
             )

    product = insert_branch_product(ctx.branch.id, price: 700)
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: ctx.branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)
    attrs = %{"cart_id" => cart.id, "branch_id" => ctx.branch.id, "fulfillment_type" => "pickup"}
    assert {:ok, order} = Orders.create_order(attrs, online: true, analytics_guest_id: guest)
    assert order.awaiting_payment
    run_report("analytics.funnel", ctx.branch)

    period = {today(ctx.branch), today(ctx.branch)}

    assert {:ok, %{rows: rows}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "funnel")

    outcome = Enum.find(rows, &(&1.dimension == "order"))
    assert outcome.counts["created"] == 1
    assert outcome.counts["converted_sessions"] == 1
    assert outcome.counts["awaiting_payment"] == 1
    assert outcome.counts["paid_online_sessions"] == 0
    assert outcome.counts["completed"] == 0

    [payment] = Payments.list(order.id)
    assert {:ok, _} = Payments.advance(Repo, order, payment, :paid, :system)
    run_report("analytics.funnel", ctx.branch)

    assert {:ok, %{rows: paid_rows}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "funnel")

    assert Enum.find(paid_rows, &(&1.dimension == "order")).counts["paid_online_sessions"] == 1
  end

  test "session source uses the first event and distinguishes direct unknown unavailable", ctx do
    enable("analytics_funnel", ctx.branch)
    direct = Ecto.UUID.generate()
    campaign = Ecto.UUID.generate()
    unknown = Ecto.UUID.generate()

    for {guest, source} <- [{direct, "direct"}, {campaign, "campaign"}, {unknown, "unknown"}] do
      assert {:ok, _} =
               Funnel.capture(
                 %{
                   "event_id" => Ecto.UUID.generate(),
                   "branch_id" => ctx.branch.id,
                   "event" => "visit",
                   "source_type" => source
                 },
                 "guest:" <> guest
               )
    end

    for {guest, later} <- [{direct, "campaign"}, {campaign, "direct"}] do
      assert {:ok, _} =
               Funnel.capture(
                 %{
                   "event_id" => Ecto.UUID.generate(),
                   "branch_id" => ctx.branch.id,
                   "event" => "menu_view",
                   "source_type" => later
                 },
                 "guest:" <> guest
               )
    end

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.query!(
      "INSERT INTO funnel_sessions(id,branch_id,owner_key,started_at,last_at) VALUES ($1::text::uuid,$2::text::uuid,$3,$4,$4)",
      [Ecto.UUID.generate(), ctx.branch.id, "guest:" <> Ecto.UUID.generate(), now]
    )

    run_report("analytics.funnel", ctx.branch)
    day = today(ctx.branch)

    assert {:ok, %{rows: rows, totals: %{"sessions" => 4}}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, {day, day}, "funnel")

    sources =
      rows
      |> Enum.filter(&(&1.dimension == "session_source"))
      |> Map.new(&{&1.key, &1.counts["sessions"]})

    assert sources == %{"direct" => 1, "campaign" => 1, "unknown" => 1, "unavailable" => 1}
  end

  test "sources report uses immutable trusted link receipt, not UTM label", ctx do
    enable("analytics_links", ctx.branch)
    enable("analytics_funnel", ctx.branch)
    guest = Ecto.UUID.generate()

    {:ok, link} =
      Links.create(ctx.analyst, ctx.branch.id, %{"campaign" => "trusted", "name" => "Trusted"})

    Repo.insert!(%Click{
      id: Ecto.UUID.generate(),
      link_id: link.id,
      branch_id: ctx.branch.id,
      guest_id: guest,
      clicked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })

    assert {:ok, _} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => ctx.branch.id,
                 "event" => "visit",
                 "source_type" => "campaign",
                 "utm_source" => "forged"
               },
               "guest:" <> guest
             )

    product = insert_branch_product(ctx.branch.id, price: 900)
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: ctx.branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    attrs = %{
      "cart_id" => cart.id,
      "branch_id" => ctx.branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }

    assert {:ok, order} = Orders.create_order(attrs, analytics_guest_id: guest)
    assert {:ok, _} = Orders.advance_order(order, :completed, :system)
    run_report("analytics.links", ctx.branch)

    assert {:ok, %{rows: [%{key: key, counts: counts}]}} =
             Reports.read(
               ctx.analyst,
               {:branch, ctx.branch.id},
               {today(ctx.branch), today(ctx.branch)},
               "sources"
             )

    assert key == link.id
    assert counts["clicks"] == 1
    assert counts["created"] == 1
    assert counts["completed"] == 1
    assert counts["revenue"] == 900
  end
end
