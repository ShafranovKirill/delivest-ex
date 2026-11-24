defmodule DelivestWeb.Staff.IntegrationLive.YandexAdsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Repo
  alias Delivest.Features
  alias Delivest.Integrations.YandexAds

  setup %{conn: conn} do
    previous = Application.get_env(:delivest, :yandex_ads_encryption_key)

    Application.put_env(
      :delivest,
      :yandex_ads_encryption_key,
      Base.encode64(:crypto.strong_rand_bytes(32))
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:delivest, :yandex_ads_encryption_key, previous),
        else: Application.delete_env(:delivest, :yandex_ads_encryption_key)
    end)

    branch = insert(:branch, is_active: true)
    assert {:ok, _} = Features.configure("yandex_costs", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("yandex_costs", {:branch, branch.id}, true, actor: "test")

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["admin", "statistics.read", "statistics.network"])
      )

    insert(:staff_branch, staff: staff, branch: branch)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}),
      staff: staff,
      branch: branch
    }
  end

  test "saves independently disabled streams and never returns stored credentials in HTML", %{
    conn: conn,
    staff: staff,
    branch: branch
  } do
    assert {:ok, _} =
             YandexAds.update_settings(staff, %{
               direct_token: "direct-secret-must-not-render",
               metrika_token: "metrika-secret-must-not-render"
             })

    {:ok, view, html} = live(conn, ~p"/staff/integrations/yandex-ads")
    refute html =~ "direct-secret-must-not-render"
    refute html =~ "metrika-secret-must-not-render"
    assert has_element?(view, "#yandex-direct_token-saved")
    assert has_element?(view, "#yandex-ads-settings")

    view
    |> form("#yandex-ads-settings",
      yandex_ads: %{
        enabled: "false",
        browser_enabled: "false",
        branch_ids: [branch.id],
        direct_token: "",
        metrika_token: ""
      }
    )
    |> render_submit()

    settings = YandexAds.get_settings()
    assert settings.direct_token == "direct-secret-must-not-render"
    refute settings.enabled
    refute settings.browser_enabled
    assert settings.branch_ids == [branch.id]
    refute render(view) =~ "direct-secret-must-not-render"
  end

  test "enables a stream from the integration settings without a separate platform switch", %{
    conn: conn,
    branch: branch
  } do
    {:ok, view, _html} = live(conn, ~p"/staff/integrations/yandex-ads")
    refute YandexAds.enabled?(:browser, branch.id)

    view
    |> form("#yandex-ads-settings",
      yandex_ads: %{
        enabled: "true",
        browser_enabled: "true",
        privacy_approved: "true",
        counter_id: "12345",
        branch_ids: [branch.id]
      }
    )
    |> render_submit()

    assert YandexAds.enabled?(:browser, branch.id)
    refute YandexAds.enabled?(:costs, branch.id)
  end

  test "OAuth application is entered in settings and its secret never appears in the form", %{
    conn: conn,
    staff: staff
  } do
    {:ok, view, html} = live(conn, ~p"/staff/integrations/yandex-ads")
    assert html =~ "yandex-oauth-redirect-uri"
    assert html =~ "/staff/integrations/yandex-ads/callback"

    changed =
      view
      |> form("#yandex-ads-settings",
        yandex_ads: %{oauth_client_id: "test-client", oauth_client_secret: "secret-not-in-html"}
      )
      |> render_change()

    refute changed =~ "secret-not-in-html"

    view
    |> form("#yandex-ads-settings",
      yandex_ads: %{oauth_client_id: "test-client", oauth_client_secret: "secret-not-in-html"}
    )
    |> render_submit()

    assert YandexAds.get_settings().oauth_client_id == "test-client"
    assert YandexAds.get_settings().oauth_client_secret == "secret-not-in-html"
    refute render(view) =~ "secret-not-in-html"
    assert has_element?(view, "#yandex-oauth_client_secret-saved")

    assert {:ok, unchanged} = YandexAds.update_settings(staff, %{oauth_client_secret: ""})
    assert unchanged.oauth_client_secret == "secret-not-in-html"
    assert {:ok, unchanged} = YandexAds.update_settings(staff, %{oauth_client_secret: "  "})
    assert unchanged.oauth_client_secret == "secret-not-in-html"
  end

  test "OAuth connect uses saved application and callback saves tokens", %{
    conn: conn,
    staff: staff
  } do
    assert {:ok, _} =
             YandexAds.update_settings(staff, %{
               oauth_client_id: "database-client",
               oauth_client_secret: "database-secret"
             })

    connected = get(conn, ~p"/staff/integrations/yandex-ads/connect")
    [location] = get_resp_header(connected, "location")
    assert URI.parse(location).host == "oauth.yandex.ru"
    query = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["client_id"] == "database-client"
    assert query["redirect_uri"] == Delivest.Integrations.YandexAds.OAuth.redirect_uri()

    Req.Test.stub(Delivest.HTTP.Client, fn request ->
      {:ok, body, request} = Plug.Conn.read_body(request)
      assert URI.decode_query(body)["client_id"] == "database-client"
      assert URI.decode_query(body)["client_secret"] == "database-secret"
      Req.Test.json(request, %{"access_token" => "from-oauth", "refresh_token" => "from-refresh"})
    end)

    callback =
      connected
      |> recycle()
      |> get(~p"/staff/integrations/yandex-ads/callback?code=valid&state=#{query["state"]}")

    assert redirected_to(callback) == ~p"/staff/integrations/yandex-ads"
    assert YandexAds.get_settings().direct_token == "from-oauth"
    assert YandexAds.get_settings().refresh_token == "from-refresh"
  end

  test "OAuth callback rejects an application changed after connect", %{conn: conn, staff: staff} do
    assert {:ok, _} =
             YandexAds.update_settings(staff, %{
               oauth_client_id: "initial-client",
               oauth_client_secret: "initial-secret"
             })

    connected = get(conn, ~p"/staff/integrations/yandex-ads/connect")
    [location] = get_resp_header(connected, "location")

    state =
      location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

    assert {:ok, _} = YandexAds.update_settings(staff, %{oauth_client_id: "replacement-client"})

    callback =
      connected
      |> recycle()
      |> get(~p"/staff/integrations/yandex-ads/callback?code=valid&state=#{state}")

    assert redirected_to(callback) == ~p"/staff/integrations/yandex-ads"
    assert is_nil(YandexAds.get_settings().direct_token)
  end

  test "non-admin cannot open or mutate advertising settings", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    assert {:error, _} = live(conn, ~p"/staff/integrations/yandex-ads")
    assert {:error, :forbidden} = YandexAds.update_settings(staff, %{enabled: true})
  end

  test "network advertising report distinguishes missing import from zero spend", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/staff/analytics/advertising")
    assert has_element?(view, "#advertising-no-costs")
    assert has_element?(view, "#advertising-coverage")
    assert has_element?(view, "#advertising-period")
    assert has_element?(view, "#advertising-import")
    assert has_element?(view, "#advertising-order-report[href^='/staff/analytics/comparison?']")
  end

  test "branch-only statistics permission does not expose account costs", %{
    conn: conn,
    branch: branch
  } do
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    assert {:error, _} = live(conn, ~p"/staff/analytics/advertising")
  end

  test "integration settings own delivery diagnostics and mapping controls", %{
    conn: conn,
    branch: branch
  } do
    order = Delivest.OrderFixtures.order_fixture(branch.id)

    issue =
      Repo.insert!(%YandexAds.Conversion{
        order_id: order.id,
        branch_id: branch.id,
        generation: 1,
        counter_id: "12345678",
        channel: "offline",
        status: "unknown",
        amount: 100,
        occurred_at: YandexAds.now()
      })

    {:ok, settings_view, _} = live(conn, ~p"/staff/integrations/yandex-ads")
    assert has_element?(settings_view, "#yandex-delivery-diagnostics #reconcile-#{issue.id}")
    assert has_element?(settings_view, "#yandex-campaign-mappings #advertising-binding-form")
    assert has_element?(settings_view, "#advertising-binding-search")

    {:ok, report_view, _} = live(conn, ~p"/staff/analytics/advertising")
    assert has_element?(report_view, "#advertising-delivery-health")
    assert has_element?(report_view, "#advertising-diagnostics-settings")
    assert has_element?(report_view, "#advertising-mapping-settings")
    refute has_element?(report_view, "#advertising-binding-form")
    refute has_element?(report_view, "#advertising-delivery-issues")
    refute has_element?(report_view, "#reconcile-#{issue.id}")
  end

  test "network reader keeps results access without settings mutation controls", %{
    conn: conn,
    branch: branch
  } do
    staff =
      insert(:staff, role: insert(:role, permissions: ["statistics.read", "statistics.network"]))

    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, view, _} = live(conn, ~p"/staff/analytics/advertising")
    assert has_element?(view, "#advertising-campaign-report")
    refute has_element?(view, "#advertising-binding-form")
    refute has_element?(view, "#advertising-mapping-settings")
    assert {:error, _} = live(conn, ~p"/staff/integrations/yandex-ads")
  end

  test "admin binds and removes campaigns from integration settings", %{
    conn: conn,
    staff: staff,
    branch: branch
  } do
    {:ok, settings} = YandexAds.update_settings(staff, %{direct_token: "test-direct-token"})

    link =
      Repo.insert!(%Delivest.Advertising.Link{
        branch_id: branch.id,
        name: "Trusted link",
        campaign: "trusted",
        token: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      })

    Repo.insert!(%YandexAds.Cost{
      generation: settings.generation,
      account: YandexAds.account_key(settings),
      day: Date.utc_today(),
      campaign_id: "123",
      campaign_name: "Imported campaign",
      cost_micros: 100,
      impressions: 1,
      clicks: 1,
      currency: "RUB",
      include_vat: true,
      updated_at: YandexAds.now()
    })

    {:ok, view, _} = live(conn, ~p"/staff/integrations/yandex-ads")

    view
    |> form("#advertising-binding-form", binding: %{link_id: link.id, campaign_id: "123"})
    |> render_submit()

    assert has_element?(view, "#binding-#{link.id}")
    {:ok, %{bindings: [binding]}} = YandexAds.Campaigns.list(staff)
    assert binding.campaign_id == "123"
    view |> element("#binding-#{link.id} button[phx-click=unbind_campaign]") |> render_click()
    refute has_element?(view, "#binding-#{link.id}")
    assert {:ok, %{bindings: []}} = YandexAds.Campaigns.list(staff)
  end

  test "advertising period is shareable and survives refresh and tab navigation", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/staff/analytics/advertising")
    query = %{period: "custom", from: "2026-10-01", to: "2026-10-08"}
    path = ~p"/staff/analytics/advertising?#{query}"

    view
    |> form("#advertising-period", period: %{from: query.from, to: query.to})
    |> render_submit()

    assert_patch(view, path)

    assert has_element?(
             view,
             "#sources-advertising-tabs a[href*='from=2026-10-01'][href*='to=2026-10-08']"
           )

    view |> element("#advertising-refresh") |> render_click()

    assert has_element?(
             view,
             "#advertising-period input[name='period[from]'][value='2026-10-01']"
           )

    {:ok, reopened, _} = live(conn, path)

    assert has_element?(
             reopened,
             "#advertising-period input[name='period[to]'][value='2026-10-08']"
           )

    render_patch(view, ~p"/staff/analytics/advertising?period=today")
    today = Delivest.LocalTime.today(Delivest.LocalTime.timezone(nil)) |> Date.to_iso8601()
    assert has_element?(view, "#advertising-period input[name='period[from]'][value='#{today}']")
  end

  test "unavailable F04 state renders dated canonical comparison link", %{conn: conn} do
    {:ok, view, _} =
      live(conn, ~p"/staff/analytics/advertising?period=custom&from=2026-10-01&to=2026-10-08")

    assert has_element?(view, "#advertising-f04-state")

    assert has_element?(
             view,
             "#advertising-order-report[href^='/staff/analytics/comparison?'][href*='from=2026-10-01'][href*='to=2026-10-08']"
           )
  end
end
