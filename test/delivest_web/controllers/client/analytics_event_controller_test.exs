defmodule DelivestWeb.Client.Analytics.EventControllerTest do
  use DelivestWeb.ConnCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Funnel, Repo}

  defp event(branch, overrides \\ %{}) do
    Map.merge(
      %{"event_id" => Ecto.UUID.generate(), "branch_id" => branch.id, "event" => "visit"},
      overrides
    )
  end

  defp enable(branch) do
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, true, actor: "host")
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM " <> table).rows |> hd() |> hd()

  test "default off and invalid payload create no raw rows or analytics jobs", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    off = post(conn, ~p"/client/analytics/events", event(branch))
    assert json_response(off, 404)
    assert count("funnel_events") == 0

    refute get_resp_header(off, "set-cookie")
           |> Enum.any?(&String.contains?(&1, "analytics_owner="))

    assert count("funnel_sessions") == 0

    assert Repo.query!("SELECT count(*) FROM background_schedules WHERE kind LIKE 'analytics.%'").rows ==
             [[0]]

    enable(branch)

    assert conn
           |> recycle()
           |> post(
             ~p"/client/analytics/events",
             event(branch, %{"client_id" => Ecto.UUID.generate()})
           )
           |> json_response(422)

    assert count("funnel_events") == 0
  end

  test "branch capability follows franchise and branch gates", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: branch.id})

    response = conn |> get(~p"/client/branches") |> json_response(200)

    assert Enum.find(response["data"], &(&1["id"] == branch.id))["branch_info"][
             "analytics_funnel_enabled"
           ] == false

    enable(branch)
    response = conn |> recycle() |> get(~p"/client/branches") |> json_response(200)

    assert Enum.find(response["data"], &(&1["id"] == branch.id))["branch_info"][
             "analytics_funnel_enabled"
           ] == true
  end

  test "guest dedupe, isolated owners and strict payload", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)
    attrs = event(branch)
    first = post(conn, ~p"/client/analytics/events", attrs)
    %{"data" => %{"session_id" => session_id}} = json_response(first, 202)

    assert get_resp_header(first, "set-cookie")
           |> Enum.any?(&String.contains?(&1, "analytics_owner="))

    second = first |> recycle() |> post(~p"/client/analytics/events", attrs)
    assert get_in(json_response(second, 202), ["data", "session_id"]) == session_id
    assert count("funnel_events") == 1
    assert count("funnel_sessions") == 1

    other = post(build_conn(), ~p"/client/analytics/events", attrs)
    assert get_in(json_response(other, 202), ["data", "session_id"]) != session_id
    assert count("funnel_events") == 2

    forged =
      build_conn()
      |> put_req_cookie("session_id", "forged-client-session")
      |> post(~p"/client/analytics/events", attrs)

    assert get_in(json_response(forged, 202), ["data", "session_id"]) not in [
             session_id,
             get_in(json_response(other, 202), ["data", "session_id"])
           ]

    assert count("funnel_events") == 3

    tampered =
      first
      |> recycle()
      |> put_req_cookie("analytics_owner", "invalid-signature")
      |> post(~p"/client/analytics/events", attrs)

    assert get_in(json_response(tampered, 202), ["data", "session_id"]) != session_id
    assert count("funnel_events") == 4

    for extra <- [
          %{"amount" => 1},
          %{"paid" => true},
          %{"timestamp" => "now"},
          %{"utm_source" => "7999-000-00-01"},
          %{"utm_campaign" => String.duplicate("a", 65)}
        ] do
      assert conn
             |> recycle()
             |> post(~p"/client/analytics/events", event(branch, extra))
             |> json_response(422)
    end
  end

  test "authenticated bearer uses client owner, even with a guest cookie", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    client = insert(:client)
    insert(:zvonok_settings)
    enable(branch)

    attrs = event(branch)
    guest = post(conn, ~p"/client/analytics/events", attrs)
    guest_session = get_in(json_response(guest, 202), ["data", "session_id"])
    token = DelivestWeb.ClientToken.issue(client.id).access_token

    authenticated =
      guest
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/client/analytics/events", attrs)

    auth_session = get_in(json_response(authenticated, 202), ["data", "session_id"])
    refute auth_session == guest_session
    assert count("funnel_events") == 2

    assert Repo.query!("SELECT owner_key FROM funnel_events WHERE session_id = $1::text::uuid", [
             auth_session
           ]).rows == [["client:" <> client.id]]
  end

  test "owner and branch scopes isolate event UUIDs and source labels are constrained" do
    first_branch = insert(:branch, is_active: true)
    second_branch = insert(:branch, is_active: true)
    enable(first_branch)

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, second_branch.id}, true,
               actor: "host"
             )

    same_id = Ecto.UUID.generate()

    attrs =
      event(first_branch, %{
        "event_id" => same_id,
        "source_type" => "campaign",
        "utm_source" => "spring",
        "utm_medium" => "social",
        "utm_campaign" => "launch-1"
      })

    assert {:ok, %{session_id: first}} = Funnel.capture(attrs, "guest:a")
    assert {:ok, %{session_id: second}} = Funnel.capture(attrs, "client:b")

    assert {:ok, %{session_id: third}} =
             Funnel.capture(%{attrs | "branch_id" => second_branch.id}, "guest:a")

    assert Enum.uniq([first, second, third]) |> length() == 3
    assert count("funnel_events") == 3

    for value <- [
          "79990000001",
          "7999-000-00-01",
          "contact@example.com",
          "https://site",
          String.duplicate("a", 65)
        ] do
      assert {:error, :invalid_payload} =
               Funnel.capture(
                 event(first_branch, %{"source_type" => "campaign", "utm_source" => value}),
                 "guest:a"
               )
    end
  end

  test "inactive branch and stale gate reject capture", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)
    attrs = event(branch)
    assert conn |> post(~p"/client/analytics/events", attrs) |> json_response(202)
    {:ok, token} = Features.snapshot("analytics_funnel", {:branch, branch.id})
    Repo.query!("UPDATE branches SET is_active = false WHERE id = $1::text::uuid", [branch.id])
    assert conn |> recycle() |> post(~p"/client/analytics/events", attrs) |> json_response(404)
    assert count("funnel_events") == 1

    Repo.query!(
      "UPDATE branches SET is_active = true, deleted_at = now() WHERE id = $1::text::uuid",
      [branch.id]
    )

    assert conn |> recycle() |> post(~p"/client/analytics/events", attrs) |> json_response(404)
    Repo.query!("UPDATE branches SET deleted_at = NULL WHERE id = $1::text::uuid", [branch.id])

    assert {:ok, _} =
             Features.configure("analytics_funnel", {:branch, branch.id}, false, actor: "host")

    assert {:error, :disabled} =
             Features.with_enabled("analytics_funnel", {:branch, branch.id}, token, fn ->
               flunk("stale gate")
             end)
  end

  test "idle boundary starts new session and duplicate does not extend it" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    owner = "guest:" <> Ecto.UUID.generate()
    attrs = event(branch)
    assert {:ok, %{session_id: first}} = Funnel.capture(attrs, owner)

    Repo.query!(
      "UPDATE funnel_sessions SET last_at = now() - interval '30 minutes' WHERE id = $1::text::uuid",
      [first]
    )

    assert {:ok, %{session_id: ^first}} = Funnel.capture(attrs, owner)
    assert {:ok, %{session_id: second}} = Funnel.capture(event(branch), owner)
    refute second == first
    assert count("funnel_sessions") == 2
  end

  test "retention is bounded and runs with feature off without touching core" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    assert {:ok, _} = Funnel.capture(event(branch), "guest:" <> Ecto.UUID.generate())
    assert {:ok, _} = Features.configure("analytics_funnel", :franchise, false, actor: "host")
    Repo.query!("UPDATE funnel_events SET received_at = now() - interval '91 days'")
    Repo.query!("UPDATE funnel_sessions SET last_at = now() - interval '91 days'")
    assert %{events: 1, sessions: 1} = Funnel.prune()
    assert count("funnel_events") == 0
    assert count("funnel_sessions") == 0
    assert Repo.get!(Delivest.Identity.Branch, branch.id)
  end

  test "retention deletes at most one batch of old events per call" do
    branch = insert(:branch, is_active: true)
    enable(branch)

    assert {:ok, %{session_id: session_id}} =
             Funnel.capture(event(branch), "guest:" <> Ecto.UUID.generate())

    Repo.query!("UPDATE funnel_events SET received_at = now() - interval '91 days'")
    Repo.query!("UPDATE funnel_sessions SET last_at = now() - interval '91 days'")

    Repo.query!(
      "INSERT INTO funnel_events (event_id, branch_id, owner_key, session_id, event, source_type, received_at) SELECT gen_random_uuid(), $1::text::uuid, 'guest:bulk', $2::text::uuid, 'visit', 'unknown', now() - interval '91 days' FROM generate_series(1, 500)",
      [branch.id, session_id]
    )

    assert {:ok, %{funnel: %{events: 500, sessions: 0}}} =
             Delivest.Logs.PruneWorker.perform(%Oban.Job{})

    assert Repo.query!(
             "SELECT count(*) FROM oban_jobs WHERE worker = 'Delivest.Logs.PruneWorker' AND args->>'continuation' = 'true'"
           ).rows == [[1]]

    assert count("funnel_events") == 1
    assert %{events: 1, sessions: 1} = Funnel.prune()
  end
end
