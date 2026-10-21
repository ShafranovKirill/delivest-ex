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
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch}
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

    {:ok, lv, _html} = live(conn, ~p"/staff/integrations")

    assert has_element?(lv, "#integration-frontpad", "Frontpad")
    assert has_element?(lv, "#main-sidebar a[href='/staff/integrations']")
  end

  test "asks for an api key when frontpad is not set up", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/integrations/frontpad")

    assert has_element?(lv, "#frontpad-not-configured")
    refute has_element?(lv, "#frontpad-refresh")
  end

  test "gets products on demand, checks the menu and waits an hour", %{
    conn: conn,
    branch: branch
  } do
    connect_frontpad(branch)
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 100)
    insert_branch_product(branch.id, name: "Tea", external_id: "9", price: 50)
    stub_catalog()

    {:ok, lv, _html} = live(conn, ~p"/staff/integrations/frontpad")
    assert has_element?(lv, "#frontpad-empty")

    lv |> element("#frontpad-refresh") |> render_click()

    assert has_element?(lv, "#frontpad-missing", "Tea")
    refute has_element?(lv, "#frontpad-missing", "Soup")
    assert has_element?(lv, "#frontpad-refresh[disabled]")
    assert has_element?(lv, "#frontpad-countdown")

    lv |> element("button[phx-value-tab=products]") |> render_click()
    assert has_element?(lv, "#frontpad-products", "Pizza")

    lv |> form("#frontpad-search", %{"q" => "sou"}) |> render_change()
    assert has_element?(lv, "#frontpad-products", "Soup")
    refute has_element?(lv, "#frontpad-products", "Pizza")
  end
end
