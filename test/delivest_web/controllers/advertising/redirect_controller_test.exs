defmodule DelivestWeb.Advertising.RedirectControllerTest do
  use DelivestWeb.ConnCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Advertising.{Attribution, Links}

  defp enable(branch) do
    assert {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("analytics_links", {:branch, branch.id}, true, actor: "host")
  end

  defp staff(branch) do
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    Repo.preload(staff, [:branches, :role])
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM " <> table).rows |> hd() |> hd()

  test "stored link redirects to configured branch without capture while disabled", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)

    assert {:ok, link} =
             Links.create(staff(branch), branch.id, %{"campaign" => "spring", "name" => "Spring"})

    assert {:ok, _} = Features.configure("analytics_links", :franchise, false, actor: "host")

    response = get(conn, ~p"/r/#{link.token}")

    assert redirected_to(response) ==
             Application.fetch_env!(:delivest, :client_origin) <> "/" <> branch.slug

    assert count("advertising_clicks") == 0

    refute Enum.any?(
             get_resp_header(response, "set-cookie"),
             &String.contains?(&1, "analytics_owner=")
           )

    assert get(build_conn(), "/r/" <> String.duplicate("a", 32)).status == 404
  end

  test "real redirect creates credible click and signed guest claim cannot be stolen", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    enable(branch)

    assert {:ok, link} =
             Links.create(staff(branch), branch.id, %{"campaign" => "spring", "name" => "Spring"})

    response = get(conn, ~p"/r/#{link.token}", %{"yclid" => "12345678901234567890"})
    assert response.status in [301, 302]
    assert count("advertising_clicks") == 1

    assert Enum.any?(
             get_resp_header(response, "set-cookie"),
             &String.contains?(&1, "analytics_owner=")
           )

    client = insert(:client)
    token = DelivestWeb.ClientToken.issue(client.id).access_token

    claimed =
      response
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/client/analytics/source/claim", %{})

    assert get_in(json_response(claimed, 200), ["data", "claimed"]) == 1
    assert Attribution.first_source(client.id).link_id == link.id

    other = insert(:client)
    other_token = DelivestWeb.ClientToken.issue(other.id).access_token

    stolen =
      response
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> other_token)
      |> post(~p"/client/analytics/source/claim", %{})

    assert get_in(json_response(stolen, 200), ["data", "claimed"]) == 0
    assert Attribution.first_source(other.id) == nil

    rotated = response |> recycle() |> get(~p"/r/#{link.token}")

    assert Enum.any?(
             get_resp_header(rotated, "set-cookie"),
             &String.contains?(&1, "analytics_owner=")
           )

    assert get_in(
             rotated
             |> recycle()
             |> put_req_header("authorization", "Bearer " <> other_token)
             |> post(~p"/client/analytics/source/claim", %{})
             |> json_response(200),
             ["data", "claimed"]
           ) == 1

    assert Attribution.first_source(other.id).link_id == link.id
  end

  test "archived links still redirect but do not capture a new click", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)
    actor = staff(branch)

    assert {:ok, link} =
             Links.create(actor, branch.id, %{"campaign" => "spring", "name" => "Spring"})

    response = get(conn, ~p"/r/#{link.token}")
    assert count("advertising_clicks") == 1
    assert {:ok, _} = Links.archive(actor, branch.id, link.id)
    assert get(build_conn(), ~p"/r/#{link.token}").status in [301, 302]
    assert count("advertising_clicks") == 1
    assert response.status in [301, 302]
  end

  test "domain ACL and forged claim input cannot create or bind sources", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other_branch = insert(:branch, is_active: true)
    enable(branch)
    actor = staff(branch)

    assert {:error, :unavailable} =
             Links.create(actor, other_branch.id, %{"campaign" => "forged", "name" => "Forged"})

    assert {:ok, link} = Links.create(actor, branch.id, %{"campaign" => "safe", "name" => "Safe"})

    response = get(conn, ~p"/r/#{link.token}")
    client = insert(:client)
    token = DelivestWeb.ClientToken.issue(client.id).access_token

    forged =
      response
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/client/analytics/source/claim", %{"client_id" => client.id})

    assert json_response(forged, 422)
    assert Attribution.first_source(client.id) == nil

    tampered =
      build_conn()
      |> put_req_cookie("analytics_owner", "tampered")
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/client/analytics/source/claim", %{})

    assert get_in(json_response(tampered, 200), ["data", "claimed"]) == 0
    assert Attribution.first_source(client.id) == nil
  end

  test "redirect carries permitted click context and legacy product keys only to its stored branch",
       %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other_branch = insert(:branch, is_active: true)
    enable(branch)

    assert {:ok, link} =
             Links.create(staff(branch), branch.id, %{"campaign" => "safe", "name" => "Safe"})

    permitted = %{
      "yclid" => "12345678901234567890",
      "campaign_id" => "98765432109876543210",
      "ad_id" => "1234567890",
      "utm_source" => "yandex",
      "utm_medium" => "cpc",
      "utm_campaign" => "autumn-menu",
      "product" => "pizza-large"
    }

    untrusted = %{
      "host" => "evil.example",
      "url" => "https://evil.example/steal",
      "redirect" => "//evil.example/steal",
      "return_to" => "/" <> other_branch.slug,
      "branch_id" => other_branch.id,
      "branch" => other_branch.slug,
      "phone" => "+79991234567",
      "utm_content" => "unreviewed-content",
      "category" => Ecto.UUID.generate()
    }

    response = get(conn, ~p"/r/#{link.token}", Map.merge(permitted, untrusted))
    destination = redirected_to(response) |> URI.parse()
    origin = Application.fetch_env!(:delivest, :client_origin) |> URI.parse()

    assert {destination.scheme, destination.host, destination.port} ==
             {origin.scheme, origin.host, origin.port}

    assert destination.path == "/" <> branch.slug
    assert URI.decode_query(destination.query) == permitted
    assert destination.fragment == nil
    assert count("advertising_clicks") == 1

    id = Ecto.UUID.generate()

    uuid_redirect =
      get(build_conn(), ~p"/r/#{link.token}", %{"product" => id})
      |> redirected_to()
      |> URI.parse()

    assert uuid_redirect.path == "/" <> branch.slug
    assert URI.decode_query(uuid_redirect.query) == %{"product" => id}
  end

  test "redirect drops malformed, oversized and structured parameters without changing the old destination",
       %{conn: conn} do
    branch = insert(:branch, is_active: true)
    enable(branch)

    assert {:ok, link} =
             Links.create(staff(branch), branch.id, %{"campaign" => "safe", "name" => "Safe"})

    invalid = %{
      "yclid" => String.duplicate("1", 129),
      "campaign_id" => "123/456",
      "ad_id" => ["123"],
      "product" => "../another-branch/product",
      "utm_source" => "79991234567",
      "utm_medium" => "person@example.com",
      "utm_campaign" => String.duplicate("a", 65)
    }

    destination = Application.fetch_env!(:delivest, :client_origin) <> "/" <> branch.slug
    assert get(conn, ~p"/r/#{link.token}", invalid) |> redirected_to() == destination
    assert get(build_conn(), ~p"/r/#{link.token}") |> redirected_to() == destination
  end
end
