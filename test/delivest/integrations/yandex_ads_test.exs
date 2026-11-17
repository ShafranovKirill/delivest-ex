defmodule Delivest.Integrations.YandexAdsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory
  import Delivest.OrderFixtures
  alias Delivest.Features
  alias Delivest.Integrations.YandexAds

  alias Delivest.Integrations.YandexAds.{
    Secret,
    Identity,
    OrderReceipt,
    Conversion,
    ConversionWorker,
    Cost,
    CostWorker,
    Api,
    ScheduleWorker
  }

  setup do
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

    branch = insert(:branch, is_active: true)

    staff =
      insert(:staff,
        role: build(:role, permissions: ["admin", "statistics.read", "statistics.network"])
      )

    %{branch: branch, staff: staff}
  end

  defp configure(%{branch: branch, staff: staff}, extra \\ %{}) do
    for feature <- ~w(yandex_browser yandex_conversions yandex_ecommerce yandex_feed yandex_costs) do
      {:ok, _} = Features.configure(feature, :franchise, true, actor: "test")
      {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "test")
    end

    attrs =
      Map.merge(
        %{
          enabled: true,
          privacy_approved: true,
          browser_enabled: true,
          conversions_enabled: true,
          counter_id: "12345678",
          branch_ids: [branch.id],
          metrika_token: "metrika-secret",
          direct_token: "direct-secret"
        },
        extra
      )

    {:ok, settings} = YandexAds.update_settings(staff, attrs)
    settings
  end

  defp complete_with_receipt(ctx, before_completion \\ fn -> :ok end) do
    settings = configure(ctx)
    owner = "guest:" <> Ecto.UUID.generate()

    {:ok, :ok} =
      capture_identity(ctx.branch.id, owner, %{
        "generation" => settings.generation,
        "client_id" => "12345678901234567890",
        "yclid" => "987654321",
        "campaign_id" => "123456789"
      })

    order = order_fixture(ctx.branch.id, price: 12_505, quantity: 2)

    {:ok, _} =
      Repo.transaction(fn ->
        YandexAds.capture_order(
          order,
          [analytics_guest_id: String.replace_prefix(owner, "guest:", "")],
          YandexAds.now()
        )
      end)

    before_completion.()
    order = order |> Ecto.Changeset.change(status: :completed) |> Repo.update!()

    {:ok, :ok} =
      Repo.transaction(fn -> YandexAds.record_transition(order, :ready, :completed) end)

    {order, Repo.get_by!(Conversion, order_id: order.id, channel: "offline"), settings}
  end

  defp capture_identity(branch_id, owner, attrs) do
    attrs =
      Map.put_new(attrs, "feature_version", YandexAds.public_config(branch_id).feature_version)

    YandexAds.capture_identity(branch_id, owner, attrs)
  end

  test "off by default: order and public configuration create no optional records", ctx do
    assert %{enabled: false, capture: false, collection_basis: "disabled"} =
             YandexAds.public_config(ctx.branch.id)

    order_fixture(ctx.branch.id)
    assert Repo.aggregate(Identity, :count) == 0
    assert Repo.aggregate(OrderReceipt, :count) == 0
    assert Repo.aggregate(Conversion, :count) == 0
    refute YandexAds.enabled?(:feed, ctx.branch.id)
  end

  test "public feature revision fences old browser buffers across platform off/on", ctx do
    settings = configure(ctx)
    original = YandexAds.public_config(ctx.branch.id)
    assert byte_size(original.feature_version) == 43

    {:ok, _} =
      Features.configure("yandex_browser", {:branch, ctx.branch.id}, false, actor: "test")

    {:ok, _} = Features.configure("yandex_browser", {:branch, ctx.branch.id}, true, actor: "test")
    current = YandexAds.public_config(ctx.branch.id)
    assert current.generation == original.generation
    refute current.feature_version == original.feature_version

    attrs = %{
      "generation" => settings.generation,
      "feature_version" => original.feature_version,
      "client_id" => "1234"
    }

    assert {:error, :invalid_or_disabled} =
             YandexAds.capture_identity(ctx.branch.id, "guest:" <> Ecto.UUID.generate(), attrs)

    assert Repo.aggregate(Identity, :count) == 0
  end

  test "credentials are authenticated ciphertext and key loss fails closed", ctx do
    settings = configure(ctx)

    %{rows: [[encrypted]]} =
      Repo.query!("SELECT metrika_token FROM yandex_ads_settings WHERE id=1")

    refute String.contains?(encrypted, "metrika-secret")
    assert {:ok, "metrika-secret"} = Secret.load(encrypted)
    assert YandexAds.get_settings().metrika_token == "metrika-secret"
    {:ok, unchanged} = YandexAds.update_settings(ctx.staff, %{"metrika_token" => ""})
    assert unchanged.generation == settings.generation

    Application.put_env(
      :delivest,
      :yandex_ads_encryption_key,
      Base.encode64(:binary.copy(<<43>>, 32))
    )

    assert %{enabled: false, credential_error: true} = YandexAds.get_settings()

    assert {:error, :credentials_unavailable} =
             YandexAds.update_settings(ctx.staff, %{enabled: false})
  end

  test "admin approval, feature gates and branch scope are independent", ctx do
    configure(ctx, %{privacy_approved: false, feed_enabled: true})
    assert %{enabled: false, capture: false} = YandexAds.public_config(ctx.branch.id)
    assert YandexAds.enabled?(:feed, ctx.branch.id)
    refute YandexAds.enabled?(:browser, Ecto.UUID.generate())
    {:ok, _} = YandexAds.update_settings(ctx.staff, %{privacy_approved: true})
    assert YandexAds.public_config(ctx.branch.id).enabled

    {:ok, _} =
      Features.configure("yandex_browser", {:branch, ctx.branch.id}, false, actor: "test")

    refute YandexAds.public_config(ctx.branch.id).enabled
  end

  test "identity payload is bounded and cannot introduce a verified identity or blank row", ctx do
    settings = configure(ctx)
    owner = "guest:" <> Ecto.UUID.generate()

    for attrs <- [
          %{"generation" => settings.generation},
          %{"generation" => settings.generation, "client_id" => "1", "phone" => "+71234567890"},
          %{"generation" => settings.generation - 1, "client_id" => "1"},
          %{"generation" => settings.generation, "yclid" => "bad,email"}
        ] do
      assert {:error, :invalid_or_disabled} =
               capture_identity(ctx.branch.id, owner, attrs)
    end

    assert Repo.aggregate(Identity, :count) == 0

    assert {:ok, :ok} =
             capture_identity(ctx.branch.id, owner, %{
               "generation" => settings.generation,
               "campaign_id" => "1234567890123"
             })

    assert Repo.one(Identity).campaign_id == "1234567890123"
  end

  test "completed conversion preserves server money, long IDs and sends once then polls", ctx do
    {order, conversion, _settings} = complete_with_receipt(ctx)
    assert conversion.amount == 25_010
    assert {:ok, csv} = ConversionWorker.prepare(conversion)
    assert csv =~ "ClientId,Yclid,Target,DateTime,Price,Currency\n"
    assert csv =~ "12345678901234567890,987654321,delivest_order_completed,"
    assert csv =~ ",250.10,RUB\n"
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      if conn.method == "POST" do
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:upload, body})
        Req.Test.json(conn, %{"uploading" => %{"id" => 98_765}})
      else
        send(test_pid, :polled)
        Req.Test.json(conn, %{"uploading" => %{"id" => 98_765, "status" => "PROCESSED"}})
      end
    end)

    job = %Oban.Job{args: %{"conversion_id" => conversion.id}}
    assert {:snooze, 60} = ConversionWorker.perform(job)
    assert_received {:upload, body}
    assert body =~ "250.10,RUB"
    assert :ok = ConversionWorker.perform(job)
    assert_received :polled
    assert Repo.get!(Conversion, conversion.id).status == "processed"
    assert :ok = ConversionWorker.perform(job)
    refute_received {:upload, _}

    {:ok, :ok} =
      Repo.transaction(fn -> YandexAds.record_transition(order, :ready, :completed) end)

    assert Repo.aggregate(Conversion, :count) == 1
  end

  test "expense and feed preferences preserve collected receipts and pending conversions", ctx do
    {order, conversion, settings} =
      complete_with_receipt(ctx, fn ->
        {:ok, _} = YandexAds.update_settings(ctx.staff, %{include_vat: false})
      end)

    assert conversion.generation == settings.generation
    assert Repo.get!(OrderReceipt, order.id).generation == settings.generation

    for attrs <- [
          %{costs_enabled: true},
          %{costs_enabled: false},
          %{feed_enabled: true},
          %{feed_enabled: false},
          %{timezone: "UTC"}
        ] do
      {:ok, changed} = YandexAds.update_settings(ctx.staff, attrs)
      assert changed.generation == settings.generation
      assert Repo.get!(Conversion, conversion.id).status == "pending"
    end

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"uploading" => %{"id" => 98_765}})
    end)

    assert {:snooze, 60} =
             ConversionWorker.perform(%Oban.Job{args: %{"conversion_id" => conversion.id}})

    assert Repo.get!(Conversion, conversion.id).status == "submitted"
  end

  for attrs <- [
        %{counter_id: "87654321"},
        %{direct_token: "another-account"},
        %{privacy_approved: false},
        %{browser_enabled: false},
        %{conversions_enabled: false}
      ] do
    test "collection change #{inspect(attrs)} invalidates pending conversions", ctx do
      {_order, conversion, settings} = complete_with_receipt(ctx)
      attrs = unquote(Macro.escape(attrs))

      {:ok, changed} = YandexAds.update_settings(ctx.staff, attrs)
      assert changed.generation > settings.generation
      assert Repo.get!(Conversion, conversion.id).status == "stale"
    end
  end

  test "changing branch scope invalidates pending conversions", ctx do
    {_order, conversion, settings} = complete_with_receipt(ctx)
    branch = insert(:branch, is_active: true)
    {:ok, changed} = YandexAds.update_settings(ctx.staff, %{branch_ids: [branch.id]})
    assert changed.generation > settings.generation
    assert Repo.get!(Conversion, conversion.id).status == "stale"
  end

  test "in-flight cost snapshots cannot publish after VAT change or expense revocation", ctx do
    settings = configure(ctx, %{costs_enabled: true})
    token = YandexAds.costs_token(settings)
    {:ok, changed} = YandexAds.update_settings(ctx.staff, %{include_vat: false})
    assert changed.generation == settings.generation

    assert {:cancel, :disabled} =
             CostWorker.publish(settings, ~D[2026-11-17], ~D[2026-11-17], [], token)

    assert is_nil(YandexAds.get_settings().costs_refreshed_at)

    {:ok, revoked} = YandexAds.update_settings(ctx.staff, %{costs_enabled: false})
    assert revoked.generation == changed.generation

    assert {:cancel, :disabled} =
             CostWorker.publish(changed, ~D[2026-11-17], ~D[2026-11-17], [], token)

    assert is_nil(YandexAds.get_settings().costs_refreshed_at)
  end

  test "queued expense imports stay revoked across settings off and on", ctx do
    settings = configure(ctx, %{costs_enabled: true})
    assert {:ok, job} = YandexAds.request_costs(ctx.staff, ~D[2026-11-17], ~D[2026-11-17])
    {:ok, _} = YandexAds.update_settings(ctx.staff, %{costs_enabled: false})
    {:ok, changed} = YandexAds.update_settings(ctx.staff, %{costs_enabled: true})
    assert changed.generation == settings.generation
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("revoked job must not issue HTTP") end)

    assert {:cancel, :disabled_or_invalid_period} =
             CostWorker.perform(Repo.get!(Oban.Job, job.id))

    assert {:ok, replacement} = YandexAds.request_costs(ctx.staff, ~D[2026-11-17], ~D[2026-11-17])
    refute replacement.id == job.id
  end

  test "changing expense basis clears published period freshness", ctx do
    settings = configure(ctx, %{costs_enabled: true})
    assert :ok = CostWorker.publish(settings, ~D[2026-11-17], ~D[2026-11-17], [])
    assert YandexAds.get_settings().costs_refreshed_at
    {:ok, changed} = YandexAds.update_settings(ctx.staff, %{include_vat: false})
    assert changed.generation == settings.generation
    assert is_nil(changed.costs_refreshed_at)
    assert is_nil(changed.costs_from)
    assert is_nil(changed.costs_to)
  end

  test "offline CSV preserves either single identifier without adding fabricated identifiers" do
    for {field, column, identifier} <- [
          {"client_id", "ClientId", "12345678901234567890"},
          {"yclid", "Yclid", "987654321"}
        ] do
      row = %Conversion{
        channel: "offline",
        amount: 123,
        occurred_at: YandexAds.now(),
        payload: %{
          field => identifier,
          "goal" => "delivest_order_completed",
          "captured_at" => DateTime.to_iso8601(YandexAds.now())
        }
      }

      assert {:ok, csv} = ConversionWorker.prepare(row)

      assert String.starts_with?(
               csv,
               "#{column},Target,DateTime,Price,Currency\n#{identifier},delivest_order_completed,"
             )

      assert length(String.split(csv, "\n", trim: true)) == 2
      assert csv =~ ",1.23,RUB\n"
    end
  end

  test "explicit funnel goal setup reuses existing goals and creates each missing browser goal once",
       ctx do
    configure(ctx)
    identifiers = YandexAds.funnel_goal_identifiers()

    existing =
      Enum.take(identifiers, 2)
      |> Enum.with_index(1)
      |> Enum.map(fn {identifier, index} ->
        %{
          "id" => index,
          "type" => "action",
          "conditions" => [%{"type" => "exact", "url" => identifier}]
        }
      end)

    goals = start_supervised!({Agent, fn -> existing end})
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      if conn.method == "GET" do
        Req.Test.json(conn, %{"goals" => Agent.get(goals, & &1)})
      else
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        goal = Jason.decode!(body)["goal"]
        identifier = get_in(goal, ["conditions", Access.at(0), "url"])
        assert identifier in identifiers
        refute identifier == "delivest_order_completed"
        assert goal["type"] == "action"
        assert get_in(goal, ["conditions", Access.at(0), "type"]) == "exact"
        send(test_pid, {:goal_created, identifier})

        id =
          Agent.get_and_update(goals, fn existing_goals ->
            id = length(existing_goals) + 1
            {id, existing_goals ++ [Map.put(goal, "id", id)]}
          end)

        Req.Test.json(conn, %{"goal" => Map.put(goal, "id", id)})
      end
    end)

    assert {:ok, %{created: created, existing: reused}} = YandexAds.ensure_funnel_goals(ctx.staff)
    assert created == Enum.drop(identifiers, 2)
    assert reused == Enum.take(identifiers, 2)
    for identifier <- created, do: assert_received({:goal_created, ^identifier})
    refute_received {:goal_created, _}

    assert {:ok, %{created: [], existing: ^identifiers}} =
             YandexAds.ensure_funnel_goals(ctx.staff)

    refute_received {:goal_created, _}
  end

  test "funnel goal setup rejects employees and reports partial failure without replaying accepted writes",
       ctx do
    configure(ctx)
    employee = insert(:staff, role: build(:role, permissions: ["integrations.read"]))

    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("employee must not invoke provider") end)

    assert {:error, :forbidden} = YandexAds.ensure_funnel_goals(employee)
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      if conn.method == "GET" do
        Req.Test.json(conn, %{"goals" => []})
      else
        index = Agent.get_and_update(counter, &{&1, &1 + 1})

        if index == 0,
          do: Req.Test.json(conn, %{"goal" => %{"id" => 42}}),
          else: Plug.Conn.send_resp(conn, 500, "Temporary failure")
      end
    end)

    assert {:error,
            %{
              created: ["delivest_visit"],
              existing: [],
              goal: "delivest_menu_view",
              reason: :goal_setup_failed
            }} = YandexAds.ensure_funnel_goals(ctx.staff)

    assert Agent.get(counter, & &1) == 2
  end

  test "unknown send is terminal and cannot duplicate a provider write", ctx do
    {_order, conversion, _} = complete_with_receipt(ctx)
    Req.Test.stub(Delivest.HTTP.Client, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    job = %Oban.Job{args: %{"conversion_id" => conversion.id}}
    assert :ok = ConversionWorker.perform(job)
    assert Repo.get!(Conversion, conversion.id).status == "unknown"
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("must not repeat unknown upload") end)
    assert :ok = ConversionWorker.perform(job)
  end

  test "interrupted send, rollback and changed destination do not send old jobs", ctx do
    {order, conversion, _} = complete_with_receipt(ctx)

    Repo.update!(
      Ecto.Changeset.change(conversion, status: "sending", attempted_at: YandexAds.now())
    )

    job = %Oban.Job{args: %{"conversion_id" => conversion.id}}
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("must not send") end)
    assert :ok = ConversionWorker.perform(job)
    assert Repo.get!(Conversion, conversion.id).status == "unknown"

    {:ok, :ok} =
      Repo.transaction(fn -> YandexAds.record_transition(order, :completed, :ready) end)

    {:ok, _} = YandexAds.update_settings(ctx.staff, %{counter_id: "87654321"})
    assert :ok = ConversionWorker.perform(job)
    assert Repo.aggregate(Conversion, :count) == 1
  end

  test "rollback before sending and re-completion still yields exactly one pending sale", ctx do
    {order, conversion, _} = complete_with_receipt(ctx)

    {:ok, :ok} =
      Repo.transaction(fn -> YandexAds.record_transition(order, :completed, :ready) end)

    assert Repo.get!(Conversion, conversion.id).status == "reverted"

    {:ok, :ok} =
      Repo.transaction(fn -> YandexAds.record_transition(order, :ready, :completed) end)

    assert Repo.get!(Conversion, conversion.id).status == "pending"
    assert Repo.aggregate(Conversion, :count) == 1
  end

  test "Reports validates TSV and preserves integer micros and malformed data", _ctx do
    tsv =
      "Date\tCampaignId\tCampaignName\tImpressions\tClicks\tCost\n2026-11-17\t123456789\tFood\t10\t2\t123456789\n"

    assert {:ok, [%{cost_micros: 123_456_789, campaign_id: "123456789"}]} =
             Api.parse_report(tsv, ~D[2026-11-17], ~D[2026-11-17])

    assert {:error, :invalid_report_row} =
             Api.parse_report(
               String.replace(tsv, "123456789\n", "1.2\n"),
               ~D[2026-11-17],
               ~D[2026-11-17]
             )

    assert {:error, :invalid_report_header} =
             Api.parse_report("wrong\n", ~D[2026-11-17], ~D[2026-11-17])

    assert 120 == Api.retry_after(%{"retryin" => ["120"]})
  end

  test "cost snapshot replaces all generations and removes vanished rows including empty response",
       ctx do
    settings = configure(ctx, %{costs_enabled: true})

    row = %{
      day: ~D[2026-11-17],
      campaign_id: "123",
      campaign_name: "Food",
      impressions: 10,
      clicks: 2,
      cost_micros: 1_234_567
    }

    assert :ok = CostWorker.publish(settings, row.day, row.day, [row])
    assert Repo.aggregate(Cost, :count) == 1
    {:ok, settings} = YandexAds.update_settings(ctx.staff, %{goal: "other_goal"})
    assert :ok = CostWorker.publish(settings, row.day, row.day, [])
    assert Repo.aggregate(Cost, :count) == 0
    assert {:ok, report} = YandexAds.report(ctx.staff, row.day, row.day)
    assert report.cost_total_micros == 0
    assert report.last_cost_update
    assert is_nil(report.roas)
  end

  test "network report requires network permissions and preserves last costs when disabled",
       ctx do
    settings = configure(ctx, %{costs_enabled: true})

    row = %{
      day: ~D[2026-11-17],
      campaign_id: "123",
      campaign_name: "Food",
      impressions: 10,
      clicks: 2,
      cost_micros: 1_234_567
    }

    :ok = CostWorker.publish(settings, row.day, row.day, [row])
    {:ok, _} = YandexAds.update_settings(ctx.staff, %{enabled: false})
    assert {:ok, %{cost_total_micros: 1_234_567}} = YandexAds.report(ctx.staff, row.day, row.day)
    branch_staff = insert(:staff, role: build(:role, permissions: ["statistics.read"]))
    assert {:error, _} = YandexAds.report(branch_staff, row.day, row.day)
  end

  test "retention removes external identifiers from conversion ledger", ctx do
    {_order, row, _} = complete_with_receipt(ctx)
    old = DateTime.add(YandexAds.now(), -91 * 86_400)
    Repo.update!(Ecto.Changeset.change(row, inserted_at: old, status: "unknown"))
    assert :ok = ScheduleWorker.prune()
    assert Repo.get!(Conversion, row.id).payload == %{}
    assert Repo.get!(Conversion, row.id).reason == "raw_identifier_retention_expired"
  end

  test "initial checkout captures independently of F04 and transaction rollback rolls back conversion intent",
       ctx do
    settings = configure(ctx)
    guest = Ecto.UUID.generate()

    assert {:ok, :ok} =
             capture_identity(ctx.branch.id, "guest:" <> guest, %{
               "generation" => settings.generation,
               "client_id" => "12345678901234567890"
             })

    product = insert_branch_product(ctx.branch.id, price: 12_505)

    {:ok, cart} =
      Delivest.Oms.Carts.create_cart(%{
        session_id: Ecto.UUID.generate(),
        branch_id: ctx.branch.id
      })

    {:ok, _, _} = Delivest.Oms.Carts.add_item(cart.id, product.id, 2)

    assert {:ok, order} =
             Delivest.Oms.Orders.create_order(
               %{
                 "cart_id" => cart.id,
                 "branch_id" => ctx.branch.id,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash"
               },
               analytics_guest_id: guest
             )

    assert Repo.get!(OrderReceipt, order.id).client_id == "12345678901234567890"
    refute Features.enabled?("analytics_funnel", {:branch, ctx.branch.id})

    assert {:error, :simulated} =
             Repo.transaction(fn ->
               YandexAds.record_transition(order, :ready, :completed)
               Repo.rollback(:simulated)
             end)

    assert Repo.aggregate(Conversion, :count) == 0

    {:ok, order} =
      Enum.reduce([:accepted, :preparing, :ready, :completed], {:ok, order}, fn status,
                                                                                {:ok, current} ->
        Delivest.Oms.Orders.advance_order(current, status, {:staff, ctx.staff})
      end)

    conversion = Repo.get_by!(Conversion, order_id: order.id)
    assert conversion.amount == 25_010
    assert [%{"price" => 12_505, "quantity" => 2}] = conversion.payload["items"]
    product |> Ecto.Changeset.change(price: 99_999) |> Repo.update!()
    assert Repo.get!(Conversion, conversion.id).payload["items"] == conversion.payload["items"]
    assert {:ok, _} = Delivest.Oms.Orders.revert_order_status(order, ctx.staff, "Mistake")
    assert Repo.get!(Conversion, conversion.id).status == "reverted"
  end

  test "claimed guest identity cannot be reused by another user on the same device", ctx do
    settings = configure(ctx)
    guest = Ecto.UUID.generate()

    {:ok, :ok} =
      capture_identity(ctx.branch.id, "guest:" <> guest, %{
        "generation" => settings.generation,
        "client_id" => "1234"
      })

    user = insert(:client)
    first = order_fixture(ctx.branch.id)

    {:ok, :ok} =
      Repo.transaction(fn ->
        YandexAds.capture_order(
          first,
          [authenticated_client_id: user.id, analytics_guest_id: guest],
          YandexAds.now()
        )
      end)

    assert Repo.get!(OrderReceipt, first.id)
    assert YandexAds.rotate_guest?("guest:" <> guest)
    second = order_fixture(ctx.branch.id)

    {:ok, :ok} =
      Repo.transaction(fn ->
        YandexAds.capture_order(second, [analytics_guest_id: guest], YandexAds.now())
      end)

    refute Repo.get(OrderReceipt, second.id)
    another = insert(:client)
    third = order_fixture(ctx.branch.id)

    {:ok, :ok} =
      Repo.transaction(fn ->
        YandexAds.capture_order(
          third,
          [authenticated_client_id: another.id, analytics_guest_id: guest],
          YandexAds.now()
        )
      end)

    refute Repo.get(OrderReceipt, third.id)
  end

  test "queued report retries the identical body and never publishes incomplete data", ctx do
    settings = configure(ctx, %{costs_enabled: true})
    parent = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      if String.ends_with?(conn.request_path, "/campaigns") do
        Req.Test.json(conn, %{
          "result" => %{
            "Campaigns" => [%{"Id" => 123, "Currency" => "RUB", "TimeZone" => "Europe/Moscow"}]
          }
        })
      else
        send(parent, {:report_request, body})
        call = Agent.get_and_update(counter, &{&1, &1 + 1})

        if call == 0 do
          conn |> Plug.Conn.put_resp_header("retryin", "120") |> Plug.Conn.send_resp(201, "")
        else
          conn
          |> Plug.Conn.put_resp_content_type("text/tab-separated-values")
          |> Plug.Conn.send_resp(
            200,
            "Date\tCampaignId\tCampaignName\tImpressions\tClicks\tCost\n2026-11-17\t123\tFood\t10\t2\t1234567\n"
          )
        end
      end
    end)

    job = %Oban.Job{
      args: %{
        "generation" => settings.generation,
        "from" => "2026-11-17",
        "to" => "2026-11-17",
        "settings_version" => YandexAds.cost_settings_version(settings),
        "feature_generations" => YandexAds.costs_token(settings)
      }
    }

    assert {:snooze, 120} = CostWorker.perform(job)
    assert_received {:report_request, first_body}
    assert Repo.aggregate(Cost, :count) == 0
    assert :ok = CostWorker.perform(job)
    assert_received {:report_request, ^first_body}
    assert Repo.one(Cost).cost_micros == 1_234_567
  end

  test "manual reconciliation only polls the supplied upload, never resends", ctx do
    {_order, row, _settings} = complete_with_receipt(ctx)
    Repo.update!(Ecto.Changeset.change(row, status: "unknown"))
    assert {:ok, :ok} = YandexAds.reconcile_delivery(ctx.staff, row.id, "777")

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      assert conn.method == "GET"
      assert String.ends_with?(conn.request_path, "/uploading/777")
      Req.Test.json(conn, %{"uploading" => %{"status" => "PROCESSED"}})
    end)

    assert :ok = ConversionWorker.perform(%Oban.Job{args: %{"conversion_id" => row.id}})
    assert Repo.get!(Conversion, row.id).status == "processed"
    assert {:error, :not_reconcilable} = YandexAds.reconcile_delivery(ctx.staff, row.id, "777")
  end

  test "selected counter and goal are checked independently", ctx do
    configure(ctx)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      cond do
        String.ends_with?(conn.request_path, "/campaigns") ->
          Req.Test.json(conn, %{"result" => %{"Campaigns" => []}})

        String.ends_with?(conn.request_path, "/goals") ->
          Req.Test.json(conn, %{"goals" => []})

        true ->
          Plug.Conn.send_resp(conn, 403, "Forbidden")
      end
    end)

    result = YandexAds.check_connections(ctx.staff)
    assert {:ok, []} = result.direct
    assert {:error, {:http_error, 403, _}} = result.metrika
    assert {:error, :selected_goal_unavailable} = result.metrika_goal
  end

  test "explicit advertiser reconnect isolates costs even without Client-Login", ctx do
    settings = configure(ctx, %{costs_enabled: true})

    row = %{
      day: ~D[2026-11-17],
      campaign_id: "123",
      campaign_name: "Owner A",
      impressions: 10,
      clicks: 2,
      cost_micros: 1_234_567
    }

    :ok = CostWorker.publish(settings, row.day, row.day, [row])
    {:ok, changed} = YandexAds.update_settings(ctx.staff, %{direct_token: "owner-b-token"})
    refute YandexAds.account_key(changed) == YandexAds.account_key(settings)
    assert is_nil(changed.costs_refreshed_at)

    assert {:ok, %{cost_total_micros: 0, costs: []}} =
             YandexAds.report(ctx.staff, row.day, row.day)

    assert Repo.aggregate(Cost, :count) == 1
  end

  test "OAuth refresh preserves advertiser namespace and destination generation", ctx do
    settings = configure(ctx, %{refresh_token: "refresh-secret"})
    vars = ~w(YANDEX_ADS_OAUTH_CLIENT_ID YANDEX_ADS_OAUTH_CLIENT_SECRET)
    previous = Map.new(vars, &{&1, System.get_env(&1)})
    Enum.each(vars, &System.put_env(&1, "test-value"))

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      assert conn.host == "oauth.yandex.ru"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert URI.decode_query(body)["grant_type"] == "refresh_token"

      Req.Test.json(conn, %{
        "access_token" => "renewed-access",
        "refresh_token" => "renewed-refresh"
      })
    end)

    assert {:ok, renewed} = YandexAds.refresh_connection(ctx.staff)
    assert renewed.account_scope == settings.account_scope
    assert renewed.generation == settings.generation
    assert renewed.direct_token == "renewed-access"
  end

  test "feature off then on never resurrects pending conversions or reports", ctx do
    {_order, conversion, _initial_settings} = complete_with_receipt(ctx)
    {:ok, settings} = YandexAds.update_settings(ctx.staff, %{costs_enabled: true})
    cost_token = YandexAds.costs_token(settings)
    # Keep a fresh stream token to exercise the independent platform gate.
    row =
      conversion
      |> Ecto.Changeset.change(
        status: "pending",
        generation: settings.generation,
        payload:
          Map.put(
            conversion.payload,
            "feature_generation",
            YandexAds.feature_token(:conversions, ctx.branch.id)
          )
      )
      |> Repo.update!()

    for feature <- ~w(yandex_conversions yandex_costs) do
      {:ok, _} = Features.configure(feature, {:branch, ctx.branch.id}, false, actor: "test")
      {:ok, _} = Features.configure(feature, {:branch, ctx.branch.id}, true, actor: "test")
    end

    Req.Test.stub(Delivest.HTTP.Client, fn _conn ->
      flunk("old generation must not issue HTTP")
    end)

    assert :ok = ConversionWorker.perform(%Oban.Job{args: %{"conversion_id" => row.id}})
    assert Repo.get!(Conversion, row.id).status == "stale"

    job = %Oban.Job{
      args: %{
        "generation" => settings.generation,
        "from" => "2026-11-17",
        "to" => "2026-11-17",
        "settings_version" => YandexAds.cost_settings_version(settings),
        "feature_generations" => cost_token
      }
    }

    assert {:cancel, :disabled_or_invalid_period} = CostWorker.perform(job)

    assert {:cancel, :disabled} =
             CostWorker.publish(settings, ~D[2026-11-17], ~D[2026-11-17], [], cost_token)
  end

  test "network permission cannot expose account data to a branch-limited employee", ctx do
    settings = configure(ctx, %{costs_enabled: true})
    other = insert(:branch, is_active: true)

    staff =
      insert(:staff, role: build(:role, permissions: ["statistics.read", "statistics.network"]))

    insert(:staff_branch, staff: staff, branch: ctx.branch)

    row = %{
      day: ~D[2026-11-17],
      campaign_id: "123",
      campaign_name: other.name,
      impressions: 1,
      clicks: 1,
      cost_micros: 999
    }

    :ok = CostWorker.publish(settings, row.day, row.day, [row])
    refute YandexAds.account_report_authorized?(staff)
    assert {:error, _} = YandexAds.report(staff, row.day, row.day)
    assert {:error, :forbidden} = YandexAds.request_costs(staff, row.day, row.day)
    assert [] = YandexAds.list_delivery_issues(staff)
  end

  test "import verifies actual provider currency before labeling spend", ctx do
    settings = configure(ctx, %{costs_enabled: true})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      assert String.ends_with?(conn.request_path, "/campaigns")

      Req.Test.json(conn, %{
        "result" => %{
          "Campaigns" => [%{"Id" => 123, "Currency" => "USD", "TimeZone" => "Europe/Moscow"}]
        }
      })
    end)

    job = %Oban.Job{
      args: %{
        "generation" => settings.generation,
        "from" => "2026-11-17",
        "to" => "2026-11-17",
        "settings_version" => YandexAds.cost_settings_version(settings),
        "feature_generations" => YandexAds.costs_token(settings)
      }
    }

    assert {:cancel, :unsupported_currency_or_timezone} = CostWorker.perform(job)
    assert Repo.aggregate(Cost, :count) == 0
  end

  test "upload validation failure is distinct from pending validation and matching", ctx do
    {_order, row, _settings} = complete_with_receipt(ctx)
    Repo.update!(Ecto.Changeset.change(row, status: "submitted", upload_id: "777"))
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

      Req.Test.json(conn, %{
        "uploading" => %{
          "status" => if(attempt == 0, do: "PREPARED", else: "PROCESSED"),
          "line_quantity" => 0,
          "source_quantity" => 1
        }
      })
    end)

    job = %Oban.Job{args: %{"conversion_id" => row.id}}
    assert {:snooze, 120} = ConversionWorker.perform(job)
    assert :ok = ConversionWorker.perform(job)

    assert %{status: "failed", reason: "provider_validated_zero_rows"} =
             Repo.get!(Conversion, row.id)
  end

  test "feed registration rejects HTTP200 operation errors and avoids duplicate URLs", ctx do
    settings = configure(ctx, %{feed_enabled: true})
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = Jason.decode!(body)

      if params["method"] == "get" do
        Req.Test.json(conn, %{"result" => %{"Feeds" => []}})
      else
        assert get_in(params, ["params", "Feeds", Access.at(0), "BusinessType"]) == "RETAIL"
        assert get_in(params, ["params", "Feeds", Access.at(0), "SourceType"]) == "URL"
        Agent.update(counter, &(&1 + 1))
        Req.Test.json(conn, %{"result" => %{"AddResults" => [%{"Errors" => [%{"Code" => 1}]}]}})
      end
    end)

    assert {:error, :feed_rejected} =
             Api.register_feed(settings, "Food", "https://example.com/feed.xml", ctx.branch.id)

    assert Agent.get(counter, & &1) == 1

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["method"] == "get"

      Req.Test.json(conn, %{
        "result" => %{
          "Feeds" => [
            %{
              "Id" => 77,
              "Status" => "DONE",
              "UrlFeed" => %{"Url" => "https://example.com/feed.xml"}
            }
          ]
        }
      })
    end)

    assert {:ok, %{id: 77, status: "DONE"}} =
             Api.register_feed(settings, "Food", "https://example.com/feed.xml", ctx.branch.id)
  end
end
