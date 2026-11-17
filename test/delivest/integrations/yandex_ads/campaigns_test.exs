defmodule Delivest.Integrations.YandexAds.CampaignsTest do
  use Delivest.DataCase, async: false
  @moduletag :repeatable_read
  import Delivest.Factory
  import Delivest.OrderFixtures
  alias Delivest.{Features, LocalTime}
  alias Delivest.Advertising.{Link, OrderAttribution}
  alias Delivest.Analytics.Reports
  alias Delivest.Analytics.Reports.Calculator
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.{Campaigns, Cost}

  @day ~D[2026-11-15]
  @zero "00000000-0000-0000-0000-000000000000"

  setup do
    branch = insert(:branch, is_active: true)
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))
    previous = Application.get_env(:delivest, :yandex_ads_encryption_key)

    Application.put_env(
      :delivest,
      :yandex_ads_encryption_key,
      Base.encode64(:binary.copy(<<42>>, 32))
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:delivest, :yandex_ads_encryption_key, previous),
        else: Application.delete_env(:delivest, :yandex_ads_encryption_key)
    end)

    {:ok, settings} = YandexAds.update_settings(admin, %{direct_token: "direct-token"})
    enable(branch)
    %{branch: branch, admin: admin, settings: settings}
  end

  defp enable(branch) do
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, true, actor: "test")

    Repo.query!(
      "UPDATE feature_audits SET inserted_at=$1 WHERE feature='analytics_links' AND scope_key IN ('franchise',$2)",
      [~U[2026-11-01 00:00:00Z], "branch:" <> branch.id]
    )
  end

  defp link(branch, name \\ "Test link") do
    Repo.insert!(%Link{
      branch_id: branch.id,
      name: name,
      campaign: "trusted_campaign",
      token: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    })
  end

  defp cost(settings, campaign \\ "123", extra \\ []) do
    Repo.update_all(Delivest.Integrations.YandexAds.Settings,
      set: [costs_refreshed_at: YandexAds.now(), costs_from: @day, costs_to: @day]
    )

    Repo.insert!(
      struct(
        Cost,
        Keyword.merge(
          [
            generation: settings.generation,
            account: YandexAds.account_key(settings),
            day: @day,
            campaign_id: campaign,
            campaign_name: "Campaign " <> campaign,
            cost_micros: 100_000_000,
            impressions: 100,
            clicks: 10,
            currency: "RUB",
            include_vat: true,
            updated_at: YandexAds.now()
          ],
          extra
        )
      )
    )
  end

  defp publish(branch, rows, day \\ @day) do
    snapshot = Ecto.UUID.generate()
    now = YandexAds.now()

    Repo.query!(
      """
      INSERT INTO analytics_report_snapshots
        (id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at)
      VALUES ($1::text::uuid,'analytics_links',$2::text::uuid,$3,1,1,1,$4,$4)
      """,
      [snapshot, branch.id, day, now]
    )

    Repo.query!(
      """
      INSERT INTO analytics_report_states
        (feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at)
      VALUES ('analytics_links',$1::text::uuid,$2,1,$3::text::uuid,$4,$4,$4,$4)
      ON CONFLICT (feature,branch_id,day) DO UPDATE SET revision=1,snapshot_id=EXCLUDED.snapshot_id,
        published_at=EXCLUDED.published_at,source_asof=EXCLUDED.source_asof
      """,
      [branch.id, day, snapshot, now]
    )

    for row <- rows do
      Repo.query!(
        "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) VALUES ($1::text::uuid,'links','link',$2,$3::text::jsonb)",
        [snapshot, row.key, Jason.encode!(row.counts)]
      )
    end

    snapshot
  end

  test "trusted revenue produces exact ratios and entry republishes late corrections",
       ctx do
    ad_link = link(ctx.branch)
    cost(ctx.settings)
    assert {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")
    order = order_fixture(ctx.branch.id, price: 12_500, quantity: 2)
    created = LocalTime.start_of_day_utc(@day, "Europe/Moscow") |> DateTime.add(3600)
    receipt_at = %{created | microsecond: {0, 6}}

    order =
      order |> Ecto.Changeset.change(status: :completed, inserted_at: created) |> Repo.update!()

    Repo.insert!(%OrderAttribution{
      order_id: order.id,
      link_id: ad_link.id,
      landing_branch_id: ctx.branch.id,
      clicked_at: DateTime.add(receipt_at, -60),
      as_of_at: receipt_at,
      inserted_at: receipt_at
    })

    payment =
      Repo.insert!(%Delivest.Payments.Payment{
        order_id: order.id,
        branch_id: ctx.branch.id,
        method: :cash,
        amount: 25_000,
        status: :paid
      })

    Repo.insert!(%Delivest.Payments.Refund{
      order_id: order.id,
      payment_id: payment.id,
      amount: 5_000,
      status: :succeeded
    })

    rows = Calculator.link_batch(ctx.branch.id, @day, @zero, 50, false)
    assert [%{counts: %{"completed" => 1, "revenue" => 20_000}}] = rows
    publish(ctx.branch, rows)
    assert {:ok, %{campaigns: [row], f04_state: :ready}} = Campaigns.report(ctx.admin, @day, @day)
    assert row.completed_orders == 1
    assert row.net_revenue == 20_000
    assert Decimal.equal?(row.roas, Decimal.new("2"))
    assert Decimal.equal?(row.cpa_micros, Decimal.new("100000000"))
    Repo.update!(Ecto.Changeset.change(order, total_amount: 99_000))

    assert {:ok, %{campaigns: [updated], f04_state: :ready, refresh_pending: false}} =
             Campaigns.report(ctx.admin, @day, @day)

    assert updated.net_revenue == 94_000
    assert Decimal.equal?(updated.roas, Decimal.new("9.4"))
  end

  test "one account campaign shared across two branches counts its spend once", ctx do
    other = insert(:branch, is_active: true)
    enable(other)
    a = link(ctx.branch)
    b = link(other)
    cost(ctx.settings)
    {:ok, _} = Campaigns.bind(ctx.admin, a.id, "123")
    {:ok, _} = Campaigns.bind(ctx.admin, b.id, "123")
    publish(ctx.branch, [%{key: a.id, counts: %{"completed" => 1, "revenue" => 12_500}}])
    publish(other, [%{key: b.id, counts: %{"completed" => 2, "revenue" => 17_500}}])

    assert {:ok, %{campaigns: [row], covered_days: 2, expected_days: 2}} =
             Campaigns.report(ctx.admin, @day, @day)

    assert row.mapping_count == 2
    assert row.completed_orders == 3
    assert row.net_revenue == 30_000
    assert row.cost_micros == 100_000_000
    assert Decimal.equal?(row.roas, Decimal.new("3"))
  end

  test "missing mappings and uncollected or disabled F04 never fabricate a ROAS", ctx do
    cost(ctx.settings)
    ad_link = link(ctx.branch)
    publish(ctx.branch, [%{key: ad_link.id, counts: %{"completed" => 2, "revenue" => 50_000}}])
    assert {:ok, %{campaigns: [missing]}} = Campaigns.report(ctx.admin, @day, @day)
    assert missing.roas == nil
    assert missing.reason == "trusted_mapping_missing"
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")

    {:ok, _} =
      Features.configure("analytics_links", {:branch, ctx.branch.id}, false, actor: "test")

    assert {:ok, %{campaigns: [disabled], f04_state: :not_collected, excluded_branches: 1}} =
             Campaigns.report(ctx.admin, @day, @day)

    assert disabled.roas == nil
    assert disabled.net_revenue == nil
  end

  test "shared account costs and mappings require full branch access, mutation is admin-only",
       ctx do
    other = insert(:branch, is_active: true)

    reader =
      insert(:staff, role: build(:role, permissions: ["statistics.read", "statistics.network"]))

    insert(:staff_branch, staff: reader, branch: ctx.branch)
    reader = Repo.preload(reader, [:role, :branches])
    ad_link = link(ctx.branch)
    cost(ctx.settings)
    assert {:error, _} = Campaigns.report(reader, @day, @day)
    assert {:error, _} = Campaigns.list(reader)
    assert {:error, _} = Campaigns.options(reader)
    assert {:error, _} = Reports.read_link_scope(reader, [other.id], {@day, @day})
    assert {:error, _} = Campaigns.bind(reader, ad_link.id, "123")
    insert(:staff_branch, staff: reader, branch: other)
    reader = Repo.preload(reader, [:branches], force: true)
    assert {:ok, _} = Campaigns.options(reader)
    assert {:error, _} = Campaigns.bind(reader, ad_link.id, "123")
  end

  test "bindings and cached expenses never cross Direct account namespace", ctx do
    ad_link = link(ctx.branch)
    cost(ctx.settings)
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")

    {:ok, settings} =
      YandexAds.update_settings(ctx.admin, %{direct_token: "different-account-token"})

    refute YandexAds.account_key(settings) == YandexAds.account_key(ctx.settings)
    assert {:ok, %{bindings: []}} = Campaigns.list(ctx.admin)
    assert {:ok, %{campaigns: []}} = Campaigns.report(ctx.admin, @day, @day)
    assert {:error, :unknown_link_or_campaign} = Campaigns.bind(ctx.admin, ad_link.id, "123")
    cost(settings, "456")
    assert {:ok, %{campaign_id: "456"}} = Campaigns.bind(ctx.admin, ad_link.id, "456")
    assert {:ok, :removed} = Campaigns.unbind(ctx.admin, ad_link.id)
    assert {:ok, %{bindings: []}} = Campaigns.list(ctx.admin)
  end

  test "bounded options and current remapping are explicit and independent of untrusted labels",
       ctx do
    ad_link = link(ctx.branch, "Searchable link")
    cost(ctx.settings, "123")
    cost(ctx.settings, "456")
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "456")

    assert {:ok, %{bindings: [%{campaign_id: "456"}], total: 1}} =
             Campaigns.list(ctx.admin, limit: 1)

    assert {:ok, %{links: [%{id: id}], campaigns: []}} =
             Campaigns.options(ctx.admin, "Searchable")

    assert id == ad_link.id
    publish(ctx.branch, [%{key: ad_link.id, counts: %{"completed" => 1, "revenue" => 15_000}}])
    assert {:ok, %{campaigns: rows, warning: warning}} = Campaigns.report(ctx.admin, @day, @day)
    assert warning =~ "historical"
    assert Enum.find(rows, &(&1.campaign_id == "123")).roas == nil
    assert Enum.find(rows, &(&1.campaign_id == "456")).net_revenue == 15_000
    assert {:error, _} = Campaigns.report(ctx.admin, @day, @day, limit: 251)
  end

  test "a busy branch refresh keeps ratios pending until its bucket can publish", ctx do
    other = insert(:branch, is_active: true)
    enable(other)
    ad_link = link(ctx.branch)
    cost(ctx.settings)
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")
    publish(ctx.branch, [%{key: ad_link.id, counts: %{"completed" => 1, "revenue" => 20_000}}])

    # Hold the same lock as an active source calculation. This makes the pending
    # state deterministic instead of relying on entry timing or bucket order.
    config = Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])
    connection = start_supervised!({Postgrex, config})
    key = "analytics-report:analytics_links:" <> other.id
    Postgrex.query!(connection, "SELECT pg_advisory_lock(hashtextextended($1,0))", [key])

    assert {:ok,
            %{
              campaigns: [row],
              f04_state: :partial,
              refresh_pending: true,
              covered_days: 1,
              expected_days: 2
            }} =
             Campaigns.report(ctx.admin, @day, @day)

    assert row.net_revenue == 20_000
    assert row.roas == nil
    assert row.reason == "f04_partial_coverage"
    Postgrex.query!(connection, "SELECT pg_advisory_unlock(hashtextextended($1,0))", [key])

    assert {:ok, %{campaigns: [complete], f04_state: :ready, refresh_pending: false}} =
             Campaigns.report(ctx.admin, @day, @day)

    assert Decimal.equal?(complete.roas, Decimal.new("2"))
  end

  test "incomplete expense periods and mixed VAT basis cannot produce misleading ROAS", ctx do
    ad_link = link(ctx.branch)
    cost(ctx.settings)
    {:ok, _} = Campaigns.bind(ctx.admin, ad_link.id, "123")
    publish(ctx.branch, [%{key: ad_link.id, counts: %{"completed" => 1, "revenue" => 20_000}}])

    Repo.update_all(Delivest.Integrations.YandexAds.Settings,
      set: [costs_from: nil, costs_to: nil]
    )

    assert {:ok, %{campaigns: [incomplete], cost_period_complete: false}} =
             Campaigns.report(ctx.admin, @day, @day)

    assert incomplete.roas == nil
    assert incomplete.reason == "cost_period_incomplete"
    next = Date.add(@day, 1)
    cost(ctx.settings, "123", day: next, include_vat: false)

    Repo.update_all(Delivest.Integrations.YandexAds.Settings,
      set: [costs_from: @day, costs_to: next]
    )

    publish(ctx.branch, [], next)
    assert {:ok, %{campaigns: [mixed]}} = Campaigns.report(ctx.admin, @day, next)
    assert mixed.cost_micros == nil
    assert mixed.roas == nil
    assert mixed.reason == "mixed_cost_basis"
  end
end
