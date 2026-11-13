defmodule DelivestWeb.Staff.IntegrationLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch}
  end

  defp sign_in_editor(conn, branch) do
    staff =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  defp connect_frontpad(branch) do
    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{provider: :frontpad, frontpad: %Frontpad.Settings{api_key: "key"}}
    })
  end

  defp stub_catalog do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "1", "1" => "2"},
        "name" => %{"0" => "Soup", "1" => "Pizza"},
        "price" => %{"0" => "100", "1" => "650"}
      })
    end)
  end

  test "lists frontpad among integrations", %{conn: conn, branch: branch} do
    connect_frontpad(branch)

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")

    assert has_element?(lv, "#integration-frontpad", "Frontpad")
    assert has_element?(lv, "#integration-zvonok")
    refute has_element?(lv, "a#integration-zvonok")
    assert has_element?(lv, "#nav-section-settings a[href='/staff/settings'].menu-active")
    refute has_element?(lv, "#main-sidebar a[href='/staff/integrations']")
    refute has_element?(lv, "#main-sidebar a[href='/staff/b/#{branch.slug}/integrations']")
  end

  test "global integrations use the header scope and preserve legacy branch links", %{
    conn: conn,
    branch: branch
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/integrations")

    refute has_element?(lv, "a#integration-zvonok")
    assert has_element?(lv, "#header-branch-#{branch.id}")
    refute has_element?(lv, "#integration-branch-selector")
    refute has_element?(lv, "#integration-frontpad")
    refute has_element?(lv, "#integration-selected-branch")

    {:ok, lv, _html} = live(conn, ~p"/staff/integrations?branch=#{branch.slug}")
    assert has_element?(lv, "#integration-selected-branch", branch.name)
    assert has_element?(lv, "#header-branch summary[aria-label='#{branch.name}']")

    assert has_element?(
             lv,
             "a#integration-frontpad[href='/staff/b/#{branch.slug}/integrations/frontpad']"
           )
  end

  test "global branch query exits explicitly when access is revoked", %{conn: conn} do
    foreign = insert(:branch)

    assert {:error, {:live_redirect, %{to: "/staff/integrations", flash: flash}}} =
             live(conn, ~p"/staff/integrations?branch=#{foreign.slug}")

    assert flash["error"] == "Permission denied"
  end

  test "global branch selection shows gateway ownership from the selected branch", %{
    conn: conn,
    branch: branch
  } do
    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{enabled: true, provider: :iiko}
    })

    {:ok, lv, _html} = live(conn, ~p"/staff/integrations?branch=#{branch.slug}")

    assert has_element?(lv, "#gateway-area-kitchen", "iiko")
    assert has_element?(lv, "#gateway-area-menu", "Delivest")
  end

  test "opens settings when frontpad is not set up", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")

    assert has_element?(lv, "#frontpad-settings fieldset[disabled]")

    refute has_element?(lv, "#staff-page-header-actions #frontpad-refresh")

    lv |> element("button[phx-value-tab=check]") |> render_click()
    assert has_element?(lv, "#frontpad-not-configured")
  end

  test "saves frontpad settings of the branch", %{conn: conn, branch: branch} do
    {:ok, lv, _html} =
      live(sign_in_editor(conn, branch), ~p"/staff/b/#{branch}/integrations/frontpad")

    lv
    |> form("#frontpad-settings",
      crm: %{enabled: "true", frontpad: %{api_key: "secret", affiliate: "7"}}
    )
    |> render_submit()

    assert has_element?(lv, "#frontpad-webhook")

    assert has_element?(lv, "#staff-page-header-actions #frontpad-refresh")

    {:ok, %{info: %{crm: crm}}} = Delivest.Identity.get_branch(branch.id, preload: [:info])
    assert crm.enabled
    assert crm.provider == :frontpad
    assert crm.frontpad.api_key == "secret"
    assert crm.frontpad.affiliate == "7"
  end

  test "enabled frontpad requires an api key", %{conn: conn, branch: branch} do
    {:ok, lv, _html} =
      live(sign_in_editor(conn, branch), ~p"/staff/b/#{branch}/integrations/frontpad")

    lv
    |> form("#frontpad-settings", crm: %{enabled: "true", frontpad: %{api_key: ""}})
    |> render_submit()

    refute has_element?(lv, "#frontpad-webhook")
    assert {:ok, %{info: nil}} = Delivest.Identity.get_branch(branch.id, preload: [:info])
  end

  test "gets products on demand, checks the menu and waits an hour", %{
    conn: conn,
    branch: branch
  } do
    connect_frontpad(branch)
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 100)
    insert_branch_product(branch.id, name: "Tea", external_id: "9", price: 50)
    stub_catalog()

    {:ok, lv, _html} =
      live(sign_in_editor(conn, branch), ~p"/staff/b/#{branch}/integrations/frontpad")

    assert has_element?(lv, "#frontpad-empty")
    refute has_element?(lv, "#frontpad-settings")

    render_click(lv, "refresh")

    assert has_element?(lv, "#frontpad-missing", "Tea")
    refute has_element?(lv, "#frontpad-missing", "Soup")

    assert has_element?(lv, "#staff-page-header-actions #frontpad-refresh[disabled]")

    assert has_element?(lv, "#staff-page-header-actions #frontpad-countdown")

    lv |> element("button[phx-value-tab=products]") |> render_click()
    assert has_element?(lv, "#frontpad-products", "Pizza")

    lv |> form("#frontpad-search", %{"q" => "sou"}) |> render_change()
    assert has_element?(lv, "#frontpad-products", "Soup")
    refute has_element?(lv, "#frontpad-products", "Pizza")
  end
end
