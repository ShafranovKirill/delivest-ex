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
    |> form("#loyalty-form", loyalty: %{enabled: "true", spend_enabled: "true"})
    |> render_submit()

    assert %LoyaltySettings{enabled: true, spend_enabled: true} = Loyalty.settings(branch.id)
    assert Loyalty.enabled?(branch.id)
  end

  test "the nav links to the page and the summary is shown", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    assert has_element?(lv, "#nav-section-main a", "Marketing")

    assert has_element?(
             lv,
             "main #staff-section-navigation #section-nav-loyalty_settings[aria-current='page']"
           )

    assert has_element?(
             lv,
             "#staff-page-header #marketing-navigation a[href='/staff/marketing/bonuses?branch=#{branch.slug}']"
           )

    assert has_element?(lv, "#loyalty-summary-liability")
    refute has_element?(lv, "#common-bonuses-form")
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

    refute has_element?(lv, "#products-#{product.id} input[name=stars_price]")
    lv |> element("#loyalty-open-product-picker") |> render_click()
    lv |> form("#loyalty-product-picker-search", search: product.name) |> render_change()

    lv
    |> element("#loyalty-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#loyalty-product-picker button[phx-click=save]") |> render_click()
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

  test "picker cancel and reopen preserve unsaved product bonuses", %{conn: conn, branch: branch} do
    first = insert_branch_product(branch.id, name: "Soup", stars_price: 20)
    second = insert_branch_product(branch.id, name: "Tea")
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    lv
    |> form("#loyalty-form", loyalty: %{enabled: "true", shop_enabled: "true"})
    |> render_submit()

    lv |> form("#bonus-form-#{first.id}", stars_price: "25", stars_reward: "3") |> render_change()
    lv |> element("#loyalty-open-product-picker") |> render_click()

    lv
    |> element("#loyalty-product-picker button.btn-outline[phx-click=cancel]")
    |> render_click()

    assert has_element?(lv, "#products-#{first.id} input[name=stars_price][value='25']")

    lv |> element("#loyalty-open-product-picker") |> render_click()
    lv |> form("#loyalty-product-picker-search", search: "Tea") |> render_change()

    lv
    |> element("#loyalty-product-picker-product-#{second.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#loyalty-product-picker button[phx-click=save]") |> render_click()
    assert has_element?(lv, "#products-#{first.id} input[name=stars_price][value='25']")
    assert has_element?(lv, "#products-#{second.id}")

    lv |> form("#bonus-form-#{second.id}", stars_price: "30") |> render_change()
    lv |> element("#save-product-bonuses") |> render_click()
    assert Repo.reload!(first).stars_price == 25
    assert Repo.reload!(second).stars_price == 30

    lv |> element("#loyalty-open-product-picker") |> render_click()
    lv |> form("#loyalty-product-picker-search", search: "Soup") |> render_change()

    lv
    |> element("#loyalty-product-picker-product-#{first.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#loyalty-product-picker button[phx-click=save]") |> render_click()
    assert Repo.reload!(first).stars_price == 25
    lv |> element("#loyalty-open-product-picker") |> render_click()
    lv |> form("#loyalty-product-picker-search", search: "Soup") |> render_change()

    lv
    |> element("#loyalty-product-picker-product-#{first.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#loyalty-product-picker button[phx-click=save]") |> render_click()
    assert has_element?(lv, "#products-#{first.id} input[name=stars_price][value='25']")
  end

  test "global bonus draft survives branch interactions", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/loyalty")

    lv
    |> form("#common-bonuses-form", settings: %{loyalty_stars: "17"})
    |> render_change()

    lv |> form("#loyalty-product-filter", search: "soup") |> render_change()

    assert has_element?(
             lv,
             ~s(#common-bonuses-form input[name="settings[loyalty_stars]"][value="17"])
           )
  end
end
