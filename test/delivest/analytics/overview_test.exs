defmodule Delivest.Analytics.OverviewTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  @moduletag :repeatable_read

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Analytics.Overview, LocalTime, Repo}
  alias Delivest.Payments.{Payment, Refund}

  setup do
    a = insert(:branch, is_active: true)
    b = insert(:branch, is_active: true)

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["statistics.read", "statistics.network", "orders.read"])
      )

    insert(:staff_branch, staff: staff, branch: a)
    insert(:staff_branch, staff: staff, branch: b)
    %{a: a, b: b, staff: Repo.preload(staff, [:role, :branches])}
  end

  test "completed net sales, late refund and cancellation use the local order day", %{
    a: a,
    b: b,
    staff: staff
  } do
    day = LocalTime.today(LocalTime.timezone(a.id))
    period = {day, day}
    completed = order_fixture(a.id, price: 15_000)
    Repo.update!(Ecto.Changeset.change(completed, status: :completed))
    created = order_fixture(a.id, price: 8_000)
    cancelled = order_fixture(b.id, price: 3_000)
    Repo.update!(Ecto.Changeset.change(cancelled, status: :cancelled))

    assert {:ok, before} = Overview.read(staff, :network, period)
    assert before.summary.revenue == 15_000
    assert before.summary.orders_count == 1
    assert before.summary.cancelled_count == 1
    assert before.summary.cancellation_rate == 50.0
    assert created.status == :created

    payment =
      Repo.insert!(%Payment{
        order_id: completed.id,
        branch_id: a.id,
        method: :cash,
        amount: 15_000,
        status: :paid
      })

    Repo.insert!(%Refund{
      order_id: completed.id,
      payment_id: payment.id,
      amount: 5_000,
      status: :succeeded
    })

    assert {:ok, after_refund} = Overview.read(staff, :network, period)
    assert after_refund.summary.revenue == 10_000
    assert after_refund.summary.refund_amount == 5_000
    assert after_refund.summary.refund_count == 1
    assert after_refund.summary.avg_check == 10_000
  end

  test "branch read rejects foreign branch and network requires network permission", %{
    a: a,
    staff: staff
  } do
    outsider = insert(:branch, is_active: true)
    period = {LocalTime.today(), LocalTime.today()}
    assert {:error, :forbidden} = Overview.read(staff, {:branch, outsider.id}, period)
    assert {:error, :forbidden} = Overview.details(staff, {:branch, outsider.id}, period, :hourly)

    assert {:error, :forbidden} =
             Overview.orders(staff, {:branch, outsider.id}, period, :completed)

    branch_only = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: branch_only, branch: a)
    branch_only = Repo.preload(branch_only, [:role, :branches])
    assert {:error, :forbidden} = Overview.read(branch_only, :network, period)
    assert {:ok, _} = Overview.read(branch_only, {:branch, a.id}, period)

    assert {:error, :forbidden} =
             Overview.orders(branch_only, {:branch, a.id}, period, :completed)
  end

  test "range is bounded before any source read", %{staff: staff} do
    assert {:error, :invalid_period} =
             Overview.read(staff, :network, {~D[2025-01-01], ~D[2026-12-01]})
  end

  test "published historical cohort becomes stale and republishes after a late refund", %{
    a: a,
    staff: staff
  } do
    day = Date.add(LocalTime.today(LocalTime.timezone(a.id)), -2)
    order = order_fixture(a.id, price: 15_000)
    at = LocalTime.start_of_day_utc(day, LocalTime.timezone(a.id)) |> DateTime.add(12 * 3600)
    Repo.update!(Ecto.Changeset.change(order, status: :completed, inserted_at: at))

    {_, _, _} =
      Overview.read(staff, {:branch, a.id}, {day, day})
      |> elem(1)
      |> then(&{&1.state, &1.summary, &1.updated_at})

    assert {:ok, _} = Delivest.Analytics.SalesCache.rebuild_day(a.id, day)
    assert {:ok, published} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert published.state == :ready
    assert published.summary.revenue == 15_000

    payment =
      Repo.insert!(%Payment{
        order_id: order.id,
        branch_id: a.id,
        method: :cash,
        amount: 15_000,
        status: :paid
      })

    Repo.insert!(%Refund{
      order_id: order.id,
      payment_id: payment.id,
      amount: 5_000,
      status: :succeeded
    })

    assert {:ok, stale} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert stale.state == :partial
    assert stale.summary.revenue == 15_000
    assert stale.updated_at == published.updated_at

    assert {:ok, _} = Delivest.Analytics.SalesCache.rebuild_day(a.id, day)
    assert {:ok, revised} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert revised.state == :ready
    assert revised.summary.revenue == 10_000
    assert revised.summary.refund_amount == 5_000
  end

  test "verified client is deduplicated across branches and prior history makes them returning",
       %{a: a, b: b, staff: staff} do
    today = LocalTime.today()
    prior = order_fixture(a.id, price: 1_000)

    at =
      LocalTime.start_of_day_utc(Date.add(today, -2), LocalTime.timezone(a.id))
      |> DateTime.add(12 * 3600)

    Repo.update!(Ecto.Changeset.change(prior, status: :completed, inserted_at: at))
    first = order_fixture(a.id, price: 2_000)
    second = order_fixture(b.id, price: 3_000)
    returning = order_fixture(b.id, price: 4_000)
    unknown = order_fixture(a.id, price: 5_000)

    for order <- [first, second, returning, unknown],
        do: Repo.update!(Ecto.Changeset.change(order, status: :completed))

    new_id = insert(:client).id
    old_id = insert(:client).id

    for {order, client_id} <- [
          {prior, old_id},
          {first, new_id},
          {second, new_id},
          {returning, old_id}
        ] do
      Repo.query!(
        "INSERT INTO analytics_order_identities(order_id,verified_client_id,owner_kind,as_of_at,inserted_at) VALUES ($1::uuid,$2::uuid,'client',now(),now())",
        [Ecto.UUID.dump!(order.id), Ecto.UUID.dump!(client_id)]
      )
    end

    assert {:ok, overview} = Overview.read(staff, :network, {today, today})
    assert overview.clients.new == 1
    assert overview.clients.returning == 1
    assert overview.clients.identified_orders == 3
    assert overview.clients.total_orders == 4
    assert overview.clients.coverage == 75.0
  end

  test "comparison caps the previous day at the same local time", %{a: a, staff: staff} do
    zone = LocalTime.timezone(a.id)
    today = LocalTime.today(zone)
    yesterday = Date.add(today, -1)

    for {hour, price} <- [{9, 1_000}, {18, 2_000}] do
      order = order_fixture(a.id, price: price)
      at = LocalTime.start_of_day_utc(yesterday, zone) |> DateTime.add(hour * 3600)
      Repo.update!(Ecto.Changeset.change(order, status: :completed, inserted_at: at))
    end

    assert {:ok, _} = Delivest.Analytics.SalesCache.rebuild_day(a.id, yesterday)
    noon = LocalTime.start_of_day_utc(today, zone) |> DateTime.add(12 * 3600)

    assert {:ok, overview} =
             Overview.read(staff, {:branch, a.id}, {today, today},
               comparison_period: {yesterday, yesterday},
               now: noon
             )

    assert overview.comparison.state == :ready
    assert overview.comparison.summary.revenue == 1_000
    assert overview.comparison.summary.orders_count == 1
    assert overview.comparison.daily == [%{date: yesterday, revenue: 1_000, orders: 1}]
    assert overview.comparison.cutoff == ~T[12:00:00]
  end

  test "published channel rows normalize hidden branch keys before totals and pagination", %{
    a: a,
    b: b
  } do
    day = LocalTime.today()

    for {branch, rows} <- [{a, [{"app", 50}, {"yandex_eda", 100}]}, {b, [{"yandex_eda", 200}]}] do
      snapshot = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.query!(
        "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::uuid,'analytics_extended',$2::uuid,$3,0,1,1,$4,$4)",
        [Ecto.UUID.dump!(snapshot), Ecto.UUID.dump!(branch.id), day, now]
      )

      Repo.query!(
        "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ('analytics_extended',$1::uuid,$2,0,$3::uuid,$4,$4,$4,$4)",
        [Ecto.UUID.dump!(branch.id), day, Ecto.UUID.dump!(snapshot), now]
      )

      for {key, revenue} <- rows do
        Repo.query!(
          "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) VALUES ($1::uuid,'extended','channel',$2,$3::text::jsonb)",
          [
            Ecto.UUID.dump!(snapshot),
            key,
            Jason.encode!(%{"revenue" => revenue, "completed" => 1})
          ]
        )
      end
    end

    visibility = %{a.id => ["app", "yandex_eda"], b.id => ["app"]}

    rows =
      Delivest.Analytics.Reports.Query.read(
        "analytics_extended",
        [a.id, b.id],
        day,
        day,
        "channels",
        %{},
        1,
        visibility
      )

    assert rows.total_rows == 3
    assert rows.totals["revenue"] == 350

    assert Map.new(rows.rows, &{&1.key, &1.counts["revenue"]}) == %{
             "app" => 50,
             "yandex_eda" => 100,
             "other" => 200
           }

    selected =
      Delivest.Analytics.Reports.Query.read(
        "analytics_extended",
        [a.id, b.id],
        day,
        day,
        "channels",
        %{"channel" => "yandex_eda"},
        1,
        visibility
      )

    assert selected.totals["revenue"] == 100
    assert Enum.map(selected.rows, & &1.key) == ["yandex_eda"]

    neutral =
      Delivest.Analytics.Reports.Query.read(
        "analytics_extended",
        [a.id, b.id],
        day,
        day,
        "channels",
        %{"channel" => "other"},
        1,
        visibility
      )

    assert neutral.total_rows == 1
    assert neutral.totals["revenue"] == 200
    assert Enum.map(neutral.rows, & &1.key) == ["other"]
  end

  test "timezone change invalidates published local day rather than serving old-zone payload", %{
    a: a,
    staff: staff
  } do
    info =
      Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: a.id,
        timezone: "Europe/Moscow"
      })

    day = Date.add(LocalTime.today("Europe/Moscow"), -2)
    order = order_fixture(a.id, price: 5_000)
    at = LocalTime.start_of_day_utc(day, "Europe/Moscow") |> DateTime.add(12 * 3600)
    Repo.update!(Ecto.Changeset.change(order, status: :completed, inserted_at: at))
    assert {:ok, _} = Delivest.Analytics.SalesCache.rebuild_day(a.id, day)
    assert {:ok, before} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert before.state == :ready
    assert before.summary.revenue == 5_000

    Repo.update!(Ecto.Changeset.change(info, timezone: "Europe/Samara"))
    Cachex.del(:branch_cache, {:timezone, a.id})
    assert {:ok, pending} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert pending.state == :partial
    refute pending.summary.revenue == 5_000
    assert {:ok, _} = Delivest.Analytics.SalesCache.rebuild_day(a.id, day)
    assert {:ok, revised} = Overview.read(staff, {:branch, a.id}, {day, day})
    assert revised.state == :ready
    assert revised.summary.revenue == 5_000
  end

  test "mixed channel settings keep hidden source in neutral other without changing overview totals",
       %{a: a, b: b, staff: staff} do
    settings = %Delivest.Integrations.Channels.BranchSettings{
      yandex_eda: %Delivest.Integrations.YandexEda.BranchSettings{enabled: true}
    }

    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: a.id, channels: settings})
    first = order_fixture(a.id, price: 1_000)
    second = order_fixture(b.id, price: 2_000)

    for order <- [first, second] do
      Repo.update!(Ecto.Changeset.change(order, status: :completed, source: "yandex_eda"))
    end

    today = LocalTime.today()
    period = {today, today}
    assert {:ok, overview} = Overview.read(staff, :network, period)
    assert overview.summary.revenue == 3_000
    assert overview.visibility.channels == ["app", "staff", "pos", "yandex_eda"]
    assert {:ok, rows} = Overview.details(staff, :network, period, :source)
    assert Map.new(rows, &{&1.key, &1.revenue}) == %{"yandex_eda" => 1_000, "other" => 2_000}

    assert {:ok, _} =
             Delivest.Features.configure("analytics_extended", :franchise, true, actor: "test")

    for branch <- [a, b] do
      assert {:ok, _} =
               Delivest.Features.configure("analytics_extended", {:branch, branch.id}, true,
                 actor: "test"
               )
    end

    assert {:ok, _} =
             Delivest.Analytics.Reports.read(staff, :network, period, "channels", %{
               "channel" => "yandex_eda"
             })

    assert {:ok, _} =
             Delivest.Analytics.Reports.read(staff, :network, period, "channels", %{
               "channel" => "other"
             })

    assert {:error, :hidden_filter} =
             Delivest.Analytics.Reports.read(staff, {:branch, b.id}, period, "channels", %{
               "channel" => "yandex_eda"
             })

    assert {:error, :hidden_filter} =
             Delivest.Analytics.Reports.read(staff, :network, period, "channels", %{
               "channel" => "frontpad"
             })
  end
end
