defmodule DelivestWeb.Staff.IntegrationLive.ZvonokTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Zvonok

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}),
      branch: branch
    }
  end

  test "saves the settings and shows the webhook url", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(lv, "a#integration-zvonok")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/zvonok")
    refute has_element?(lv, "#zvonok-webhook")
    refute Zvonok.configured?()

    lv
    |> form("#zvonok-settings",
      zvonok: %{public_key: "key", campaign_id: "42", webhook_token: "my-secret-token"}
    )
    |> render_submit()

    assert has_element?(lv, "#zvonok-webhook", "/integrations/zvonok/my-secret-token")
    assert %{public_key: "key", campaign_id: "42"} = Zvonok.get_settings()
    assert Zvonok.valid_webhook_token?("my-secret-token")
    refute Zvonok.valid_webhook_token?("other")
  end

  test "an empty token is replaced with a random one", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/zvonok")

    lv
    |> form("#zvonok-settings",
      zvonok: %{public_key: "key", campaign_id: "42", webhook_token: ""}
    )
    |> render_submit()

    assert %{webhook_token: token} = Zvonok.get_settings()
    assert byte_size(token) >= 8
  end

  test "is closed without the admin permission", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, _redirect} = live(conn, ~p"/staff/b/#{branch}/integrations/zvonok")
  end
end
