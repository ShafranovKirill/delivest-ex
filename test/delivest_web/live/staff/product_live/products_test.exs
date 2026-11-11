defmodule DelivestWeb.Staff.ProductLive.ProductsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Repo, Relations}
  alias DelivestWeb.Staff.ProductLive.ProductTags

  test "product section matches only the branch product namespace" do
    assert ProductTags.section("/staff/b/north/products") == :products
    assert ProductTags.section("/staff/b/north/products/123/edit") == :products
    assert ProductTags.section("/staff/b/north/products/tags/new") == :tags
    assert ProductTags.section("/staff/b/north/products/bulk") == :bulk
    assert ProductTags.section("/staff/b/north/products-foo") == nil
    assert ProductTags.section("/staff/products") == :products
  end

  test "static product HTML has direct tabs before LiveView connects", %{conn: conn} do
    branch = insert(:branch, name: "Center")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    conn = get(conn, ~p"/staff/b/#{branch}/products/tags")
    html = html_response(conn, 200)
    document = LazyHTML.from_document(html)

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#staff-header[data-header-layout='product-tabs'] #product-section-tab-tags[aria-current='page']"
             )
           )

    assert Enum.empty?(LazyHTML.query(document, "#staff-header #staff-header-context"))
    assert Enum.empty?(LazyHTML.query(document, "#staff-header #staff-header-title"))
    assert Enum.empty?(LazyHTML.query(document, "#staff-page-header"))
  end

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

    test "renders tabs directly in the header and actions in a portal", %{
      conn: conn
    } do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")

      actions_portal = render(element(lv, "#staff-page-header-actions"))

      assert has_element?(
               lv,
               "#staff-header[data-header-layout='product-tabs'][data-header-actions='true']"
             )

      assert has_element?(
               lv,
               "#staff-header #staff-page-header-navigation[aria-label='Products']"
             )

      assert has_element?(lv, "#staff-header [role='tablist'] [role='tab']")
      refute has_element?(lv, "#staff-page-header")
      refute has_element?(lv, "#staff-header-context")
      refute has_element?(lv, "#staff-header-title")
      assert has_element?(lv, "main h1.sr-only")
      assert actions_portal =~ ~s(data-phx-portal="#staff-header-actions-scroll")
      assert actions_portal =~ ~s(id="copy-products-trigger")
      assert actions_portal =~ ~s(id="export-products")
      assert actions_portal =~ ~s(id="bulk-add-products")
      assert actions_portal =~ ~s(id="create-product")
      assert has_element?(lv, "main #products-filter")
      refute has_element?(lv, "main #products-filter [role='tablist']")
    end

    test "each product section selects its tab in the direct header", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      for {path, key, title, actions?} <- [
            {"", "products", "Products", true},
            {"/stops", "stops", "Stop list", false},
            {"/modifiers", "modifiers", "Modifiers", true},
            {"/tags", "tags", "Tags", true},
            {"/suggested", "suggested", "Recommended", false},
            {"/bulk", "products", "Bulk add products", true}
          ] do
        {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products" <> path)

        assert has_element?(
                 lv,
                 "#staff-header[data-header-layout='product-tabs'][data-header-actions='#{actions?}']"
               )

        assert has_element?(
                 lv,
                 "#staff-header #product-section-tab-#{key}[aria-current='page'][aria-selected='true']"
               )

        for other <- ~w(products stops modifiers tags suggested) do
          assert has_element?(lv, "#staff-header #product-section-tab-#{other}[role='tab']")

          if other != key,
            do:
              refute(
                has_element?(
                  lv,
                  "#staff-header #product-section-tab-#{other}[aria-current='page']"
                )
              )
        end

        assert has_element?(lv, "main h1.sr-only", title)
        refute has_element?(lv, "#staff-page-header")
        refute has_element?(lv, "#staff-header-context")

        if actions? do
          assert render(element(lv, "#staff-page-header-actions")) =~
                   ~s(data-phx-portal="#staff-header-actions-scroll")
        else
          refute has_element?(lv, "#staff-page-header-actions")
        end
      end
    end

    test "read-only sections have no header actions", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      for section <- ["modifiers", "tags"] do
        {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products" <> "/" <> section)
        assert has_element?(lv, "#staff-header[data-header-actions='false'] [role='tablist']")
        refute render(element(lv, "#staff-page-header-actions")) =~ ~s(class="btn)
      end
    end

    test "read-only staff sees export but no create actions", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")

      actions_portal = render(element(lv, "#staff-page-header-actions"))
      assert actions_portal =~ ~s(id="export-products")
      refute actions_portal =~ ~s(id="copy-products-trigger")
      refute actions_portal =~ ~s(id="bulk-add-products")
      refute actions_portal =~ ~s(id="create-product")
    end
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
