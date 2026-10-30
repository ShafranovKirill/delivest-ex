defmodule DelivestWeb.Staff.IntegrationLive.IikoTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.{Crm, Iiko}

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
  end

  test "the key is saved, then organization and terminal group are picked from iiko", ctx do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      case conn.request_path do
        "/api/1/access_token" ->
          Req.Test.json(conn, %{"token" => "jwt"})

        "/api/1/organizations" ->
          Req.Test.json(conn, %{"organizations" => [%{"id" => "org-1", "name" => "Пиццерия"}]})

        "/api/1/terminal_groups" ->
          Req.Test.json(conn, %{
            "terminalGroups" => [%{"items" => [%{"id" => "tg-1", "name" => "Зал"}]}]
          })

        "/api/1/payment_types" ->
          Req.Test.json(conn, %{"paymentTypes" => [%{"id" => "pt-1", "name" => "Наличные"}]})
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations/iiko")

    lv
    |> form("#iiko-settings", crm: %{iiko: %{api_key: "key"}})
    |> render_submit()

    lv |> element("#iiko-load") |> render_click()
    assert render(lv) =~ "Пиццерия"

    lv
    |> form("#iiko-settings",
      crm: %{
        enabled: "true",
        iiko: %{organization_id: "org-1", terminal_group_id: "tg-1", cash_payment_type_id: "pt-1"}
      }
    )
    |> render_submit()

    assert %{enabled: true, provider: :iiko, iiko: %Iiko.Settings{api_key: "key"} = settings} =
             Crm.get_branch_settings(ctx.branch.id)

    assert settings.terminal_group_id == "tg-1"
    assert Iiko.configured?(settings)
  end
end
