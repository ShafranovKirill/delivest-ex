defmodule DelivestWeb.Staff.IntegrationLive.YandexAdsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

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
end
