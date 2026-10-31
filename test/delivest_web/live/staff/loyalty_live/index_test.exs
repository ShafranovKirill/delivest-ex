defmodule DelivestWeb.Staff.LoyaltyLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Loyalty
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: [
              "promotions.read",
              "promotions.update",
              "clients.read",
              "clients.update"
            ]
          )
      )

    insert(:staff_branch, staff: staff, branch: branch)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}),
      branch: branch
    }
  end

  test "the settings are saved for the branch", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    lv
    |> form("#loyalty-form", loyalty: %{enabled: "true", per_rubles: "50", stars: "3"})
    |> render_submit()

    assert %LoyaltySettings{enabled: true, per_rubles: 50, stars: 3} = Loyalty.settings(branch.id)
    assert Loyalty.enabled?(branch.id)
  end

  test "the nav links to the page and the summary is shown", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    assert has_element?(lv, ~s(#main-sidebar a[href="/staff/b/#{branch.slug}/loyalty"]))
    assert has_element?(lv, "#loyalty-summary-liability")
  end

  test "the client card lets a manager correct the balance", %{conn: conn, branch: branch} do
    Repo.get_by!(BranchInfo, branch_id: branch.id)
    |> BranchInfo.changeset(%{"loyalty" => %{"enabled" => true}})
    |> Repo.update!()

    Cachex.clear(:branch_cache)
    client = insert(:client)

    {:ok, lv, _html} = live(conn, ~p"/staff/clients/#{client.id}")

    lv
    |> form("#loyalty-adjust-form", amount: "40", reason: "apology")
    |> render_submit()

    assert Loyalty.balance(client.id) == 40
    assert has_element?(lv, "#client-loyalty-balance", "40")
  end

  test "bonus settings control reward products without catalog permissions", %{
    conn: conn,
    branch: branch
  } do
    product = insert_branch_product(branch.id)
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    lv
    |> form("#loyalty-form", loyalty: %{enabled: "true", shop_enabled: "true"})
    |> render_submit()

    assert has_element?(lv, "#products-#{product.id} input[name=stars_price]")

    lv
    |> form("#bonus-form-#{product.id}", stars_price: "25", stars_reward: "3")
    |> render_change()

    assert is_nil(Repo.reload!(product).stars_price)
    lv |> form("#loyalty-product-filter", search: "no matching product") |> render_change()
    lv |> form("#loyalty-product-filter", search: "") |> render_change()
    assert has_element?(lv, "#products-#{product.id} input[name=stars_price][value='25']")
    lv |> element("#save-product-bonuses") |> render_click()

    saved = Repo.reload!(product)
    assert saved.stars_price == 25
    assert saved.stars_reward == 3
    assert Loyalty.shop_enabled?(branch.id)
  end

  test "the table filters configured products including zero rewards", %{
    conn: conn,
    branch: branch
  } do
    configured = insert_branch_product(branch.id, name: "Soup", stars_reward: 0)
    unconfigured = insert_branch_product(branch.id, name: "Tea")
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/loyalty")
    assert has_element?(lv, "#loyalty-configured-count", "1")
    lv |> form("#loyalty-product-filter", configured: "true", search: "") |> render_change()
    assert has_element?(lv, "#products-#{configured.id}")
    refute has_element?(lv, "#products-#{unconfigured.id}")
    lv |> form("#loyalty-product-filter", configured: "true", search: "Tea") |> render_change()
    refute has_element?(lv, "#products-#{configured.id}")
  end
end
