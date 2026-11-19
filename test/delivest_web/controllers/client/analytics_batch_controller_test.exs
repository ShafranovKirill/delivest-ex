defmodule DelivestWeb.Client.Analytics.BatchControllerTest do
  use DelivestWeb.ConnCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Funnel, Repo}

  defp event(branch, name \\ "visit"),
    do: %{"event_id" => Ecto.UUID.generate(), "branch_id" => branch.id, "event" => name}

  defp enable(branch) do
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM " <> table).rows |> hd() |> hd()

  test "batch preserves order, partial duplicates and legacy single dedupe", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)
    first = event(branch)
    second = event(branch, "menu_view")
    third = event(branch, "product_view")

    packet = conn |> post(~p"/client/analytics/events/batch", %{"events" => [first, second]})
    %{"data" => %{"events" => acknowledgements}} = json_response(packet, 202)
    assert Enum.map(acknowledgements, & &1["event_id"]) == [first["event_id"], second["event_id"]]
    [first_ack, second_ack] = acknowledgements
    assert first_ack["session_id"] == second_ack["session_id"]
    assert count("funnel_events") == 2
    assert count("funnel_sessions") == 1
    assert [first["event_id"], second["event_id"]] ==
             (Repo.query!("SELECT event_id::text FROM funnel_events ORDER BY id").rows
              |> Enum.map(fn [id] -> id end))

    partial =
      packet
      |> recycle()
      |> post(~p"/client/analytics/events/batch", %{"events" => [second, third, second]})

    assert %{"data" => %{"events" => [duplicate, new_ack, repeated]}} =
             json_response(partial, 202)

    assert duplicate == second_ack
    assert repeated == second_ack
    assert new_ack["event_id"] == third["event_id"]
    assert count("funnel_events") == 3
    assert count("funnel_sessions") == 1

    assert partial |> recycle() |> post(~p"/client/analytics/events", first) |> json_response(202)
    assert count("funnel_events") == 3

    Repo.query!("UPDATE funnel_sessions SET last_at = now() - interval '30 minutes'")

    only_duplicates =
      partial
      |> recycle()
      |> post(~p"/client/analytics/events/batch", %{"events" => [first, second]})

    assert json_response(only_duplicates, 202)
    assert count("funnel_sessions") == 1
  end

  test "mixed or invalid packet never writes and gate revocation blocks the packet", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    enable(branch)
    valid = event(branch)

    for packet <- [
          [valid, event(other)],
          [valid, Map.put(event(branch), "amount", 12)],
          [valid, nil],
          [valid, 42],
          [valid, []],
          [valid, "invalid"],
          []
        ] do
      assert conn
             |> recycle()
             |> post(~p"/client/analytics/events/batch", %{"events" => packet})
             |> json_response(422)
    end

    assert count("funnel_events") == 0
    assert count("funnel_sessions") == 0

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, false, actor: "host")

    assert conn
           |> recycle()
           |> post(~p"/client/analytics/events/batch", %{"events" => [valid]})
           |> json_response(404)

    assert count("funnel_events") == 0
  end

  test "batch shares the 60 logical event rate budget with single requests", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)
    conn = %{conn | remote_ip: {203, 0, 113, 117}}

    for _ <- 1..3 do
      packet = for _ <- 1..20, do: event(branch)

      assert conn
             |> recycle()
             |> post(~p"/client/analytics/events/batch", %{"events" => packet})
             |> json_response(202)
    end

    assert conn
           |> recycle()
           |> post(~p"/client/analytics/events", event(branch))
           |> json_response(429)

    assert count("funnel_events") == 60
  end

  test "direct bulk capture and legacy single share one owner session" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    owner = "guest:" <> Ecto.UUID.generate()
    first = event(branch)
    second = event(branch)
    assert {:ok, %{session_id: session_id}} = Funnel.capture(first, owner)
    assert {:ok, %{events: [same, new]}} = Funnel.capture_many([first, second], owner)
    assert same.session_id == session_id
    assert new.session_id == session_id
    assert count("funnel_events") == 2
  end

  test "competing packet and legacy insert the shared event only once" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    owner = "guest:" <> Ecto.UUID.generate()
    shared = event(branch)
    extra = event(branch, "menu_view")

    results =
      [:single, :batch]
      |> Task.async_stream(
        fn
          :single -> Funnel.capture(shared, owner)
          :batch -> Funnel.capture_many([shared, extra], owner)
        end,
        max_concurrency: 2,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM funnel_events WHERE branch_id = $1::text::uuid AND owner_key = $2",
               [branch.id, owner]
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM funnel_sessions WHERE branch_id = $1::text::uuid AND owner_key = $2",
               [branch.id, owner]
             ).rows
  end
end
