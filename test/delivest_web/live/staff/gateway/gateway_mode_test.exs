defmodule DelivestWeb.Staff.GatewayModeTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  @permissions ~w(orders.read orders.update orders.deliver orders.cook pos.use integrations.read)

  defp setup_branch(conn, crm) do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    staff = insert(:staff, role: insert(:role, permissions: @permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
  end

  describe "a branch without crm" do
    setup %{conn: conn}, do: setup_branch(conn, nil)

    test "shows every section", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts")

      refute has_element?(lv, "#gateway-note")
      assert has_element?(lv, ~s(#main-sidebar a[href="/staff/b/#{branch.slug}/couriers"]))
      assert has_element?(lv, ~s(a[href="/staff/b/#{branch.slug}/finance/receipts"]))
    end
  end

  describe "a branch on iiko" do
    setup %{conn: conn},
      do: setup_branch(conn, %{enabled: true, provider: :iiko})

    test "hides the sections iiko runs from the menu", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

      for page <- ~w(couriers deliveries receipts pos kitchen) do
        refute has_element?(lv, ~s(#main-sidebar a[href="/staff/b/#{branch.slug}/#{page}"]))
      end

      assert has_element?(lv, ~s(a[href="/staff/b/#{branch.slug}/orders"]))
    end

    test "the header names the gateway", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#gateway-badge", "iiko")
    end

    test "the integrations page lists who runs what", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations")

      assert has_element?(lv, "#gateway-area-kitchen", "iiko")
      assert has_element?(lv, "#gateway-area-menu", "Delivest")
    end

    test "a direct visit shows the note instead of the page", %{conn: conn, branch: branch} do
      for page <- ~w(finance/receipts couriers deliveries) do
        {:ok, lv, _html} = live(conn, "/staff/b/#{branch.slug}/#{page}")

        assert has_element?(lv, "#gateway-note", "iiko")
      end
    end
  end

  describe "a branch on frontpad" do
    setup %{conn: conn},
      do: setup_branch(conn, %{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}})

    test "keeps receipts and couriers", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/receipts")

      refute has_element?(lv, "#gateway-note")
    end
  end

  describe "a branch whose menu comes from the crm" do
    setup %{conn: conn} do
      branch = insert(:branch)

      Repo.insert!(%BranchInfo{
        branch_id: branch.id,
        crm: %{enabled: true, provider: :iiko, menu_source: :crm}
      })

      role = insert(:role, permissions: ~w(products.read products.create products.delete))
      staff = insert(:staff, role: role)
      insert(:staff_branch, staff: staff, branch: branch)
      %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
    end

    test "hides creating and bulk adding products", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products")

      refute has_element?(lv, ~s(a[href$="/products/bulk"]))
      refute has_element?(lv, ~s(a[href*="/products/new"]))
    end

    test "bulk add redirects back to the list", %{conn: conn, branch: branch} do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/staff/b/#{branch}/products/bulk")

      assert to == "/staff/b/#{branch.slug}/products"
    end
  end

  test "a branch without crm has no badge", %{conn: conn} do
    %{conn: conn, branch: branch} = setup_branch(conn, nil)
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

    refute has_element?(lv, "#gateway-badge")
  end
end
