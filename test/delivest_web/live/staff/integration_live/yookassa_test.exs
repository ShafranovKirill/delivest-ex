defmodule DelivestWeb.Staff.IntegrationLive.YookassaTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Yookassa

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}),
      branch: branch
    }
  end

  test "saves the shop and shows the webhook url", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(lv, "a#integration-yookassa")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yookassa")
    refute has_element?(lv, "#yookassa-webhook")

    lv
    |> form("#yookassa-settings", yookassa: %{shop_id: "506751", secret_key: "live_secret"})
    |> render_submit()

    assert has_element?(lv, "#yookassa-webhook", "/integrations/yookassa/")
    assert Yookassa.configured?()
    assert Yookassa.valid_webhook_token?(Yookassa.get_settings().webhook_token)
  end

  test "the check warns when the shop already sends receipts", %{conn: conn, branch: branch} do
    Delivest.Repo.insert!(%Yookassa.Settings{shop_id: "506751", secret_key: "k"})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "account_id" => "506751",
        "status" => "enabled",
        "test" => true,
        "fiscalization" => %{"enabled" => true, "provider" => "atol"}
      })
    end)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yookassa")
    lv |> element("#yookassa-check") |> render_click()

    assert has_element?(lv, "#yookassa-receipts-conflict", "atol")
  end

  test "the check reports rejected keys", %{conn: conn, branch: branch} do
    Delivest.Repo.insert!(%Yookassa.Settings{shop_id: "506751", secret_key: "bad"})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"type" => "error"})
    end)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/yookassa")
    lv |> element("#yookassa-check") |> render_click()

    assert has_element?(lv, "#yookassa-shop-error")
  end
end
