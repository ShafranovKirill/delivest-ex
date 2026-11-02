defmodule DelivestWeb.Staff.IntegrationLive.IikoTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.{Crm, Iiko}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Repo

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

  test "the menu is checked and applied from iiko", ctx do
    alias Delivest.Identity.Branch.BranchInfo
    alias Delivest.Integrations.Crm.BranchSettings

    Delivest.Repo.insert!(%BranchInfo{
      branch_id: ctx.branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :iiko,
        iiko: %Iiko.Settings{api_key: "k", organization_id: "o", terminal_group_id: "t"}
      }
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      case conn.request_path do
        "/api/1/access_token" ->
          Req.Test.json(conn, %{"token" => "jwt"})

        "/api/1/nomenclature" ->
          Req.Test.json(conn, %{
            "groups" => [],
            "products" => [
              %{
                "id" => "p-1",
                "name" => "Лимонад",
                "type" => "Good",
                "sizePrices" => [%{"price" => %{"currentPrice" => 150}}]
              }
            ]
          })
      end
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations/iiko")
    lv |> element("button[phx-value-tab=menu]") |> render_click()
    lv |> element("#iiko-menu-check") |> render_click()
    assert lv |> element("#iiko-menu-plan") |> render() =~ "Лимонад"

    lv |> element("#iiko-menu-apply") |> render_click()
    assert %{price: 15_000} = Delivest.Repo.get_by!(Delivest.Net.Product, name: "Лимонад")
  end

  test "saving keys keeps another active crm and explains the switch", ctx do
    activate_frontpad(ctx.branch)

    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations/iiko")

    assert has_element?(lv, "#iiko-provider-switch", "Frontpad")

    lv
    |> form("#iiko-settings", crm: %{iiko: %{api_key: "iiko-key"}})
    |> render_submit()

    assert %{enabled: true, provider: :frontpad, iiko: %Iiko.Settings{api_key: "iiko-key"}} =
             Crm.get_branch_settings(ctx.branch.id)
  end

  test "explicitly enabling iiko switches the active crm", ctx do
    activate_frontpad(ctx.branch)
    stub_iiko()

    {:ok, lv, _html} = live(ctx.conn, ~p"/staff/b/#{ctx.branch}/integrations/iiko")

    lv
    |> form("#iiko-settings", crm: %{iiko: %{api_key: "iiko-key"}})
    |> render_submit()

    lv |> element("#iiko-load") |> render_click()

    lv
    |> form("#iiko-settings",
      crm: %{
        enabled: "true",
        iiko: %{
          organization_id: "org-1",
          terminal_group_id: "tg-1"
        }
      }
    )
    |> render_submit()

    assert %{enabled: true, provider: :iiko} = Crm.get_branch_settings(ctx.branch.id)
  end

  defp activate_frontpad(branch) do
    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "frontpad-key"}
      }
    })
  end

  defp stub_iiko do
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
  end
end
