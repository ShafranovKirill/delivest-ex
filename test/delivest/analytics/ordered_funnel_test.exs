defmodule Delivest.Analytics.OrderedFunnelTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Analytics.Reports.{FunnelPresentation, OrderedFunnel}
  alias Delivest.Funnel.OrderCapture
  alias Delivest.{Features, Funnel, LocalTime, Repo}

  setup do
    branch = insert(:branch, is_active: true)

    started =
      LocalTime.start_of_day_utc(
        LocalTime.today(LocalTime.timezone(branch.id)),
        LocalTime.timezone(branch.id)
      )

    %{branch: branch, started: started}
  end

  defp session(branch, started, suffix) do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO funnel_sessions(id,branch_id,owner_key,started_at,last_at) VALUES ($1::text::uuid,$2::text::uuid,$3,$4,$4)",
      [id, branch.id, "guest:" <> suffix, started]
    )

    id
  end

  defp event(branch, session_id, name, at) do
    Repo.query!(
      """
      INSERT INTO funnel_events(event_id,branch_id,owner_key,session_id,event,source_type,received_at)
      VALUES ($1::text::uuid,$2::text::uuid,$3,$4::text::uuid,$5,'unknown',$6)
      """,
      [Ecto.UUID.generate(), branch.id, "guest:" <> session_id, session_id, name, at]
    )
  end

  defp counts(branch, started) do
    OrderedFunnel.calculate(branch.id, started, DateTime.add(started, 86_400, :second))
    |> Map.new(fn row -> {row.key, row.counts} end)
  end

  test "100-session cohort has ordered reach, previous and start rates", %{
    branch: branch,
    started: started
  } do
    for n <- 1..100 do
      id = session(branch, started, Integer.to_string(n))
      if n <= 80, do: event(branch, id, "menu_view", DateTime.add(started, 1, :second))
      if n <= 40, do: event(branch, id, "cart_add", DateTime.add(started, 2, :second))
      if n <= 30, do: event(branch, id, "checkout_start", DateTime.add(started, 3, :second))

      if n <= 24 do
        order_id = Ecto.UUID.generate()
        at = DateTime.add(started, 4, :second)

        Repo.query!(
          """
          INSERT INTO orders(id,number,branch_id,cart_id,status,fulfillment_type,payment_method,total_amount,inserted_at,updated_at,source,business_date,daily_number)
          VALUES ($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,'new','pickup','cash',100,$5,$5,'web',$6,$7)
          """,
          [
            order_id,
            "funnel-" <> Integer.to_string(n),
            branch.id,
            Ecto.UUID.generate(),
            at,
            LocalTime.today(LocalTime.timezone(branch.id)),
            n
          ]
        )

        Repo.query!(
          """
          INSERT INTO funnel_order_receipts(order_id,session_id,owner_kind,session_started_at,session_last_at,source_type,as_of_at,inserted_at)
          VALUES ($1::text::uuid,$2::text::uuid,'guest',$3,$4,'unknown',$4,$4)
          """,
          [order_id, id, started, at]
        )

        if n == 1 do
          second_order = Ecto.UUID.generate()

          Repo.query!(
            """
            INSERT INTO orders(id,number,branch_id,cart_id,status,fulfillment_type,payment_method,total_amount,inserted_at,updated_at,source,business_date,daily_number)
            VALUES ($1::text::uuid,'funnel-second-order',$2::text::uuid,$3::text::uuid,'new','pickup','cash',100,$4,$4,'web',$5,101)
            """,
            [
              second_order,
              branch.id,
              Ecto.UUID.generate(),
              at,
              LocalTime.today(LocalTime.timezone(branch.id))
            ]
          )

          Repo.query!(
            """
            INSERT INTO funnel_order_receipts(order_id,session_id,owner_kind,session_started_at,session_last_at,source_type,as_of_at,inserted_at)
            VALUES ($1::text::uuid,$2::text::uuid,'guest',$3,$4,'unknown',$4,$4)
            """,
            [second_order, id, started, at]
          )
        end
      end
    end

    result = counts(branch, started)

    assert Enum.map(
             ~w(session_started menu_view cart_add checkout_start order_created),
             &result[&1]["sessions"]
           ) ==
             [100, 80, 40, 30, 24]

    assert Enum.map(
             ~w(menu_view cart_add checkout_start order_created),
             &result[&1]["from_previous_percent"]
           ) ==
             [80.0, 50.0, 75.0, 80.0]

    assert result["order_created"]["from_start_percent"] == 24.0
    assert result["session_started"]["lost_to_next"] == 20
  end

  test "duplicate and reversed events do not invent reach; direct product and quick add are covered",
       %{branch: branch, started: started} do
    reversed = session(branch, started, "reversed")
    direct = session(branch, started, "direct")
    quick = session(branch, started, "quick")
    event(branch, reversed, "checkout_start", DateTime.add(started, 1, :second))
    event(branch, reversed, "cart_add", DateTime.add(started, 2, :second))
    event(branch, reversed, "menu_view", DateTime.add(started, 3, :second))
    event(branch, direct, "product_view", DateTime.add(started, 1, :second))
    event(branch, direct, "product_view", DateTime.add(started, 1, :second))
    event(branch, direct, "cart_add", DateTime.add(started, 2, :second))
    event(branch, quick, "cart_add", DateTime.add(started, 1, :second))

    result = counts(branch, started)

    assert Enum.map(
             ~w(session_started menu_view cart_add checkout_start order_created),
             &result[&1]["sessions"]
           ) ==
             [3, 3, 3, 0, 0]

    assert result["paths"]["direct_product_entry"] == 1
    assert result["paths"]["quick_add_entry"] == 2
    assert result["paths"]["checkout_without_cart_event"] == 0
    assert result["paths"]["checkout_out_of_order"] == 1
    assert result["order_created"]["from_previous_percent"] == nil
  end

  test "equal timestamps use event id order and receipt cannot predate checkout",
       %{branch: branch, started: started} do
    id = session(branch, started, "ties")
    at = DateTime.add(started, 2, :second)
    event(branch, id, "menu_view", at)
    event(branch, id, "cart_add", at)
    event(branch, id, "checkout_start", at)

    order_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO orders(id,number,branch_id,cart_id,status,fulfillment_type,payment_method,total_amount,inserted_at,updated_at,source,business_date,daily_number)
      VALUES ($1::text::uuid,'funnel-before-checkout',$2::text::uuid,$3::text::uuid,'new','pickup','cash',100,$4,$4,'web',$5,201)
      """,
      [
        order_id,
        branch.id,
        Ecto.UUID.generate(),
        started,
        LocalTime.today(LocalTime.timezone(branch.id))
      ]
    )

    Repo.query!(
      """
      INSERT INTO funnel_order_receipts(order_id,session_id,owner_kind,session_started_at,session_last_at,source_type,as_of_at,inserted_at)
      VALUES ($1::text::uuid,$2::text::uuid,'guest',$3,$3,'unknown',$3,$3)
      """,
      [order_id, id, started]
    )

    result = counts(branch, started)
    assert result["checkout_start"]["sessions"] == 1
    assert result["order_created"]["sessions"] == 0
    assert result["paths"]["quick_add_entry"] == 0
    assert result["paths"]["linked_order_without_checkout"] == 0
    assert result["paths"]["linked_order_before_checkout"] == 1
  end

  test "after-midnight events and 30-minute order attribution remain in starting day",
       %{branch: branch, started: midnight} do
    zone = LocalTime.timezone(branch.id)
    previous = LocalTime.start_of_day_utc(Date.add(LocalTime.today(zone), -1), zone)
    opening = DateTime.add(midnight, -10 * 60, :second)
    id = session(branch, opening, "rollover")
    event(branch, id, "menu_view", DateTime.add(midnight, -5 * 60, :second))
    event(branch, id, "cart_add", DateTime.add(midnight, 2 * 60, :second))
    checkout = DateTime.add(midnight, 3 * 60, :second)
    event(branch, id, "checkout_start", checkout)
    Repo.query!("UPDATE funnel_sessions SET last_at=$1 WHERE id=$2::text::uuid", [checkout, id])

    order_id = Ecto.UUID.generate()
    at = DateTime.add(midnight, 5 * 60, :second)

    Repo.query!(
      """
      INSERT INTO orders(id,number,branch_id,cart_id,status,fulfillment_type,payment_method,total_amount,inserted_at,updated_at,source,business_date,daily_number)
      VALUES ($1::text::uuid,'funnel-rollover',$2::text::uuid,$3::text::uuid,'new','pickup','cash',100,$4,$4,'web',$5,301)
      """,
      [order_id, branch.id, Ecto.UUID.generate(), at, LocalTime.today(zone)]
    )

    assert :ok =
             OrderCapture.capture(
               %{id: order_id, branch_id: branch.id},
               "guest:rollover",
               DateTime.add(at, 0, :microsecond)
             )

    prior = counts(branch, previous)

    assert Enum.map(
             ~w(session_started menu_view cart_add checkout_start order_created),
             &prior[&1]["sessions"]
           ) == [1, 1, 1, 1, 1]

    assert counts(branch, midnight)["session_started"]["sessions"] == 0
  end

  test "capture opens a new branch-local session after 30 minutes of inactivity",
       %{branch: branch} do
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "test")

    owner = "guest:" <> Ecto.UUID.generate()

    assert {:ok, %{session_id: first}} =
             Funnel.capture(
               %{
                 "branch_id" => branch.id,
                 "event_id" => Ecto.UUID.generate(),
                 "event" => "visit"
               },
               owner
             )

    Repo.query!(
      "UPDATE funnel_sessions SET last_at=timezone('UTC',now())-interval '31 minutes' WHERE id=$1::text::uuid",
      [first]
    )

    assert {:ok, %{session_id: second}} =
             Funnel.capture(
               %{
                 "branch_id" => branch.id,
                 "event_id" => Ecto.UUID.generate(),
                 "event" => "menu_view"
               },
               owner
             )

    refute first == second
  end

  test "empty cohort has nil rates and no losses", %{branch: branch, started: started} do
    result = counts(branch, started)
    assert result["session_started"]["sessions"] == 0
    assert result["menu_view"]["from_previous_percent"] == nil
    assert result["checkout_start"]["lost_to_next"] == 0
    assert result["order_created"]["from_start_percent"] == nil
  end

  test "presentation aggregates versioned buckets and rejects legacy counts", %{branch: branch} do
    day = LocalTime.today(LocalTime.timezone(branch.id))
    other = insert(:branch)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "test")

    for b <- [branch, other] do
      assert {:ok, _} =
               Features.configure("analytics_funnel", {:branch, b.id}, true, actor: "test")
    end

    for {b, version, values} <- [
          {branch, 2, [60, 48, 24, 18, 12]},
          {other, 2, [40, 32, 16, 12, 12]}
        ] do
      snapshot = Ecto.UUID.generate()
      assert {:ok, generation} = Features.snapshot("analytics_funnel", {:branch, b.id})

      Repo.query!(
        """
        INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at)
        VALUES ($1::text::uuid,'analytics_funnel',$2::text::uuid,$3,0,$4,$5,$6,$6)
        """,
        [snapshot, b.id, day, generation.franchise, generation.branch, now]
      )

      Repo.query!(
        """
        INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at)
        VALUES ('analytics_funnel',$1::text::uuid,$2,0,$3::text::uuid,$4,$4,$4,$4)
        """,
        [b.id, day, snapshot, now]
      )

      for {key, n} <-
            Enum.zip(~w(session_started menu_view cart_add checkout_start order_created), values) do
        Repo.query!(
          """
          INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts)
          VALUES ($1::text::uuid,'funnel','stage',$2,$3::text::jsonb)
          """,
          [snapshot, key, Jason.encode!(%{"algorithm_version" => version, "sessions" => n})]
        )
      end
    end

    data = %{rows: [], total_rows: 0, totals: %{"sessions" => 0}}
    result = FunnelPresentation.apply(data, [branch.id, other.id], day, day, nil)
    assert result.legacy_days == 0
    assert Enum.map(Enum.take(result.rows, 5), & &1.counts["sessions"]) == [100, 80, 40, 30, 24]
    assert Enum.at(result.rows, 2).counts["from_previous_percent"] == 50.0

    Repo.query!(
      """
      UPDATE analytics_report_rows SET counts=jsonb_set(counts,'{algorithm_version}','1'::jsonb)
      WHERE key='session_started' AND snapshot_id=(
        SELECT snapshot_id FROM analytics_report_states
        WHERE feature='analytics_funnel' AND branch_id=$1::text::uuid AND day=$2
      )
      """,
      [other.id, day]
    )

    mixed = FunnelPresentation.apply(data, [branch.id, other.id], day, day, nil)
    assert mixed.legacy_days == 1
    assert Enum.at(mixed.rows, 0).counts["sessions"] == 60
    assert Enum.at(mixed.rows, 5).counts["legacy_snapshot_days"] == 1

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, false, actor: "test")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "test")

    stale = FunnelPresentation.apply(data, [branch.id, other.id], day, day, nil)
    assert stale.legacy_days == 2
    assert Enum.at(stale.rows, 0).counts["sessions"] == 0
  end
end
