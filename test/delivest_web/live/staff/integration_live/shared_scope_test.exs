defmodule DelivestWeb.Staff.IntegrationLive.SharedScopeTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias DelivestWeb.Staff.IntegrationLive.Presentation

  test "shared context has no branch and network scope" do
    context = Presentation.context(nil)

    assert context.branch == nil
    assert Presentation.state(:zvonok, context).scope == {:network, nil}
    assert Presentation.state(:dadata, context).scope == {:network, nil}
    assert Presentation.state(:yookassa, context).usage == []
    assert Presentation.state(:yandex_eda, context).usage == []
  end

  test "admin opens shared settings without an active branch", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin", "integrations.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    for path <- [
          ~p"/staff/integrations/zvonok",
          ~p"/staff/integrations/dadata",
          ~p"/staff/integrations/yookassa",
          ~p"/staff/integrations/yandex-eda"
        ] do
      assert {:ok, lv, _html} = live(conn, path)
      assert render(element(lv, "#staff-page-header")) =~ ~s(href="/staff/integrations")
      assert render(lv) =~ "All branches"
    end
  end

  test "reader cannot open shared settings without an active branch", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, _redirect} = live(conn, ~p"/staff/integrations/yandex-eda")
  end
end
