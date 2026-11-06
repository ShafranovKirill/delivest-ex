defmodule DelivestWeb.Staff.IntegrationLive.FrontpadTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Frontpad

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "read-only staff cannot trigger refresh or stop sync events", %{conn: conn} do
    branch = insert(:branch)
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("Frontpad must not be called") end)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read"]),
        ~p"/staff/b/#{branch}/integrations/frontpad"
      )

    render_hook(lv, "refresh", %{})
    render_hook(lv, "sync_stops", %{})
    assert has_element?(lv, "#frontpad-guide")
  end

  test "payment codes and order marks are saved", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/frontpad"
      )

    assert has_element?(lv, "#frontpad-guide[open]")

    lv
    |> form("#frontpad-settings",
      crm: %{
        frontpad: %{
          api_key: "secret",
          payments: %{cash: "1", card_offline: "2", online: "317"},
          tags: %{app: "1500", yandex_eda: "1363", paid_online: "1291"}
        }
      }
    )
    |> render_submit()

    frontpad = Crm.get_branch_settings(branch.id).frontpad
    assert %{cash: "1", card_offline: "2", online: "317"} = frontpad.payments
    assert %{app: "1500", yandex_eda: "1363", paid_online: "1291", staff: nil} = frontpad.tags
  end

  test "letters in codes are rejected", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/frontpad"
      )

    html =
      lv
      |> form("#frontpad-settings", crm: %{frontpad: %{payments: %{online: "card"}}})
      |> render_change()

    assert html =~ "has invalid format" or html =~ "неверный формат"
  end

  test "a successful save updates the status without a reload", %{conn: conn} do
    branch = insert(:branch)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/frontpad"
      )

    assert has_element?(lv, "#frontpad-health-summary-credentials", "Not filled in")

    lv
    |> form("#frontpad-settings",
      crm: %{enabled: "true", frontpad: %{api_key: "secret"}}
    )
    |> render_submit()

    assert has_element?(lv, "#frontpad-health-summary-credentials", "Filled in")
    assert has_element?(lv, "#frontpad-health-summary-usage", "On")
  end

  test "an invalid save keeps the saved status and its connection check", %{conn: conn} do
    branch = insert(:branch)

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      crm: %Delivest.Integrations.Crm.BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Delivest.Integrations.Frontpad.Settings{api_key: "key"}
      }
    })

    assert {:ok, _status} = Health.report(:frontpad, branch.id, Frontpad, :ok)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["integrations.read", "integrations.update"]),
        ~p"/staff/b/#{branch}/integrations/frontpad"
      )

    lv |> element("button[phx-value-tab=settings]") |> render_click()
    assert render(lv) =~ "Connection checked"

    lv
    |> form("#frontpad-settings",
      crm: %{frontpad: %{api_key: "other", payments: %{online: "card"}}}
    )
    |> render_submit()

    assert render(lv) =~ "Connection checked"
    assert Crm.get_branch_settings(branch.id).frontpad.api_key == "key"
  end

  test "the connection check shows the result here and on the integrations card", %{conn: conn} do
    branch = insert(:branch)

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      crm: %Delivest.Integrations.Crm.BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Delivest.Integrations.Frontpad.Settings{api_key: "key"}
      }
    })

    conn = sign_in(conn, branch, ["integrations.read", "integrations.update"])
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    lv |> element("button[phx-value-tab=settings]") |> render_click()
    assert render(lv) =~ "Connection not checked"

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "error", "error" => "invalid_secret"})
    )

    assert lv |> element("#frontpad-health-check") |> render_click() =~ "Access error"

    {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert html =~ "Access error"

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "success", "error" => "no_stops"})
    )

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    lv |> element("button[phx-value-tab=settings]") |> render_click()
    assert lv |> element("#frontpad-health-check") |> render_click() =~ "Connection checked"
  end
end
