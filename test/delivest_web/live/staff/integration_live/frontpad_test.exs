defmodule DelivestWeb.Staff.IntegrationLive.FrontpadTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
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
    assert render(lv) =~ "The connection has not been checked"

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "error", "error" => "invalid_secret"})
    )

    assert lv |> element("#frontpad-health-check") |> render_click() =~
             "reconnect the integration"

    {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert html =~ "Reconnect"

    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"result" => "success", "error" => "no_stops"})
    )

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    lv |> element("button[phx-value-tab=settings]") |> render_click()
    assert lv |> element("#frontpad-health-check") |> render_click() =~ "Connected"
  end
end
