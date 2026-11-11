defmodule DelivestWeb.Staff.ProductLive.ProductsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Repo, Relations}

  test "branch editor sees a refusal when editing a shared product", %{conn: conn} do
    own = insert(:branch)
    other = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read", "products.update"]))
    insert(:staff_branch, staff: staff, branch: own)
    product = insert(:product, name: "Old", price: 100)
    Relations.create_relation(Repo, "Branch", own.id, "Product", product.id)
    Relations.create_relation(Repo, "Branch", other.id, "Product", product.id)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => own.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{own}/products/#{product.id}/edit")

    lv |> form("#product-form", product: %{name: "New", price: 100}) |> render_submit()
    assert has_element?(lv, "#product-save-error")
    assert Repo.get!(Delivest.Net.Product, product.id).name == "Old"
  end

  test "branch editor cannot attach groups while saving a shared product", %{conn: conn} do
    own = insert(:branch)
    other = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read", "products.update"]))
    insert(:staff_branch, staff: staff, branch: own)
    product = insert(:product, name: "Old", price: 100)
    group = Repo.insert!(%Delivest.Net.ModifierGroup{name: "Size", min: 0, max: 1})
    Relations.create_relation(Repo, "Branch", own.id, "Product", product.id)
    Relations.create_relation(Repo, "Branch", other.id, "Product", product.id)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => own.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{own}/products/#{product.id}/edit")

    lv
    |> form("#product-form",
      product: %{name: "Old", price: 100},
      modifier_group_ids: [group.id]
    )
    |> render_submit()

    assert has_element?(lv, "#product-save-error")
    assert Delivest.Net.Modifiers.group_ids(product.id) == []
    assert Repo.get!(Delivest.Net.Product, product.id).name == "Old"
  end

  describe "products management page" do
    test "renders the products page and filter controls with a selected branch", %{conn: conn} do
      branch = insert(:branch, name: "North Branch")
      admin_role = insert(:role, permissions: ["admin"])
      staff = insert(:staff, role: admin_role)

      conn =
        init_test_session(conn, %{
          "staff_id" => staff.id,
          "active_branch_id" => branch.id
        })

      {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/products")

      assert html =~ "Products"
      assert html =~ "Create Product"
      assert html =~ "All categories"
      assert html =~ "All statuses"
    end

    test "page links preserve search and sorting without accumulating filters", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      for n <- 1..11, do: insert_branch_product(branch.id, name: "Match #{n}", price: 100)
      insert_branch_product(branch.id, name: "Other")

      {:ok, lv, _html} =
        live(conn, ~p"/staff/b/#{branch}/products?search=Match&page=1&page_size=10")

      first_page_ids = product_row_ids(lv)
      assert length(first_page_ids) == 10

      next_href =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(".join a:last-child")
        |> LazyHTML.attribute("href")
        |> List.first()

      assert next_href
      query = next_href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert query["search"] == "Match"
      refute String.contains?(next_href, "filters[")

      lv |> element(".join a:last-child") |> render_click()
      assert_patch(lv, next_href)
      assert length(product_row_ids(lv)) == 1
      assert product_row_ids(lv) -- first_page_ids == product_row_ids(lv)

      {:ok, reloaded, _html} = live(conn, next_href)
      assert product_row_ids(reloaded) == product_row_ids(lv)

      {:ok, back, _html} =
        live(conn, ~p"/staff/b/#{branch}/products?search=Match&page=1&page_size=10")

      assert product_row_ids(back) == first_page_ids

      lv |> element("table thead th:nth-child(2) a") |> render_click()
      first_sort_url = assert_patch(lv)
      assert String.contains?(first_sort_url, "order_by[]=name")
      assert String.contains?(first_sort_url, "order_directions[]=asc")
      assert length(product_row_ids(lv)) == 10
      assert product_first_name(lv) == "Match 1"

      lv |> element("table thead th:nth-child(2) a") |> render_click()
      second_sort_url = assert_patch(lv)
      assert String.contains?(second_sort_url, "order_directions[]=desc")
      assert length(product_row_ids(lv)) == 10
      assert product_first_name(lv) == "Match 9"
    end
  end

  defp product_row_ids(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tbody#products tr[id]")
    |> LazyHTML.attribute("id")
  end

  defp product_first_name(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tbody#products tr:first-child td:nth-child(2)")
    |> LazyHTML.text()
    |> String.trim()
  end

  test "uploaded image goes to the product form", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, media} =
      Delivest.Media.create_file(%{
        "bucket" => "delivest",
        "key" => "product/x.jpg",
        "original_name" => "x.jpg",
        "mime_type" => "image/jpeg",
        "size" => 1,
        "context" => "product",
        "is_private" => false,
        "owner_id" => staff.id
      })

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/new")
    send(lv.pid, {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, [{:ok, media}]}})

    _ = render(lv)
    assert render(lv) =~ "Change Image"

    assert [%{worker: "Delivest.Media.Workers.ThumbnailWorker"}] =
             Oban.Testing.all_enqueued(Delivest.Repo, [])
  end

  test "tags are picked from the configured tags and can be cleared", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    hit = Delivest.Repo.get_by!(Delivest.Net.ProductTag, name: "Хит")
    spicy = Delivest.Repo.get_by!(Delivest.Net.ProductTag, name: "Острое")

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/products/new")
    assert html =~ "Острое"

    lv
    |> form("#product-form", product: %{name: "Том ям", price: 450, tags: ["", spicy.id, hit.id]})
    |> render_submit()

    {:ok, {[product], _meta}} =
      Delivest.Net.Products.list_staff_products_for_branch(staff, branch.id)

    assert Enum.sort(product.tags) == Enum.sort([hit.id, spicy.id])

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/#{product.id}/edit")
    lv |> form("#product-form", product: %{tags: [""]}) |> render_submit()

    assert %{tags: []} = Delivest.Net.Products.get_product(product.id)
  end

  test "modifier groups are attached to the product", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    group = Delivest.Repo.insert!(%Delivest.Net.ModifierGroup{name: "Размер", min: 1, max: 1})

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/products/new")
    assert html =~ "Размер"

    lv
    |> form("#product-form",
      product: %{name: "Пицца", price: 450},
      modifier_group_ids: ["", group.id]
    )
    |> render_submit()

    {:ok, {[product], _meta}} =
      Delivest.Net.Products.list_staff_products_for_branch(staff, branch.id)

    assert Delivest.Net.Modifiers.group_ids(product.id) == [group.id]
  end

  test "nutrition and excise are saved with the product", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/new")

    lv
    |> form("#product-form",
      product: %{
        name: "Морс",
        price: 120,
        calories: "45.5",
        proteins: "0",
        fats: "0",
        carbohydrates: "11.2",
        excise: "sugary_drink"
      }
    )
    |> render_submit()

    {:ok, {[product], _meta}} =
      Delivest.Net.Products.list_staff_products_for_branch(staff, branch.id)

    assert %{calories: 45.5, proteins: +0.0, carbohydrates: 11.2, excise: :sugary_drink} =
             Delivest.Net.Products.get_product(product.id)
  end

  describe "copying products" do
    setup %{conn: conn} do
      branch = insert(:branch, name: "Source")
      target = insert(:branch, name: "Target")
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))

      conn =
        init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      %{conn: conn, branch: branch, target: target}
    end

    test "copies the selected products", %{conn: conn, branch: branch, target: target} do
      chosen =
        insert_branch_product(branch.id,
          name: "Chosen",
          measure_unit: :ml,
          calories: 40.0,
          excise: :sugary_drink
        )

      insert_branch_product(branch.id, name: "Skipped")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products")

      lv |> element("#product-selection") |> render_change(%{"ids" => [chosen.id]})
      render_click(lv, "open_copy")

      lv
      |> form("#copy-products-form", %{"target_branch_id" => target.id, "scope" => "selected"})
      |> render_submit()

      assert render(lv) =~ "Products copied: 1"
      assert [copy_id] = Delivest.Relations.list_target_ids("Branch", target.id, "Product")

      assert %{measure_unit: :ml, calories: 40.0, excise: :sugary_drink} =
               Delivest.Net.Products.get_product(copy_id)
    end

    test "copies every product of the branch", %{conn: conn, branch: branch, target: target} do
      insert_branch_product(branch.id, name: "One")
      insert_branch_product(branch.id, name: "Two")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products")
      render_click(lv, "open_copy")

      lv
      |> form("#copy-products-form", %{"target_branch_id" => target.id, "scope" => "all"})
      |> render_submit()

      assert length(Delivest.Relations.list_target_ids("Branch", target.id, "Product")) == 2
    end
  end

  describe "stop list" do
    setup %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
      %{conn: conn, branch: branch}
    end

    test "staff stops a product for today and lifts it", %{conn: conn, branch: branch} do
      soup = insert_branch_product(branch.id, name: "Soup")
      insert_branch_product(branch.id, name: "Tea")
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products")

      lv
      |> element("#product-stop-#{soup.id} button[phx-value-period=today]")
      |> render_click()

      assert render(lv) =~ "Stop until"
      assert Delivest.Net.Stops.stopped?(branch.id, soup.id)

      lv |> element("#product-stop-#{soup.id} button[phx-click=resume]") |> render_click()
      refute Delivest.Net.Stops.stopped?(branch.id, soup.id)
    end

    test "the stop list filter shows only stopped products", %{conn: conn, branch: branch} do
      soup = insert_branch_product(branch.id, name: "Soup")
      insert_branch_product(branch.id, name: "Kompot")
      {:ok, _} = Delivest.Net.Stops.replace_external(branch.id, :frontpad, [soup.id])

      {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/products?stopped=true")

      assert html =~ "Soup"
      refute html =~ "Kompot"
      assert html =~ "Stop in Frontpad"
    end
  end
end
