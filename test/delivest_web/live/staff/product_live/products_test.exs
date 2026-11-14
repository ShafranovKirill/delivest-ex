defmodule DelivestWeb.Staff.ProductLive.ProductsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Repo, Relations}
  alias DelivestWeb.Staff.ProductLive.ProductTags

  test "product section matches only the branch product namespace" do
    assert ProductTags.section("/staff/b/north/products") == :products
    assert ProductTags.section("/staff/b/north/products/123/edit") == :products
    assert ProductTags.section("/staff/b/north/products/tags/new") == :tags
    assert ProductTags.section("/staff/b/north/products/bulk") == :bulk
    assert ProductTags.section("/staff/b/north/products/operations") == nil
    assert ProductTags.section("/staff/b/north/products-foo") == nil
    assert ProductTags.section("/staff/products") == :products
    assert ProductTags.section("/staff/menu/popular") == :popular
    assert ProductTags.section("/staff/b/north/menu/popular") == :popular
    assert ProductTags.section("/staff/b/north/menu/popular/other") == nil
    assert ProductTags.section("/staff/b/north/menu/popular-other") == nil
  end

  test "static product HTML has selected local navigation before LiveView connects", %{conn: conn} do
    branch = insert(:branch, name: "Center")
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    conn = get(conn, ~p"/staff/b/#{branch}/products/tags")
    html = html_response(conn, 200)
    document = LazyHTML.from_document(html)

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#staff-context-navigation #staff-section-navigation #product-section-tab-tags[aria-current='page']"
             )
           )

    assert Enum.empty?(LazyHTML.query(document, "#staff-header #staff-header-context"))
    assert Enum.any?(LazyHTML.query(document, "main #staff-page-header h1"))
    assert Enum.any?(LazyHTML.query(document, "main #staff-page-header-actions"))
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

  test "a new product shows errors only after validation and submission", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/products/new")
    refute has_element?(view, "#product-error-summary")

    view |> form("#product-form", product: %{name: "", price: ""}) |> render_change()
    assert has_element?(view, "#product-error-summary a[href='#product_name']")
    assert has_element?(view, "#product-error-summary a[href='#product_price']")

    view |> form("#product-form", product: %{name: "", price: ""}) |> render_submit()
    assert has_element?(view, "#product-error-summary a[href='#product_name']")
    assert has_element?(view, "#product-error-summary a[href='#product_price']")
  end

  test "minimal creation requires a price, accepts zero, and starts unpublished", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products/new")
    assert has_element?(lv, "#product-main-section")
    assert has_element?(lv, "#product-advanced-fields")
    lv |> element("#product-advanced-fields summary") |> render_click()
    assert has_element?(lv, "#product-advanced-fields[open]")

    assert has_element?(
             lv,
             "#product-form input[name='product[is_active]'][type='checkbox']:not(:checked)"
           )

    lv |> form("#product-form", product: %{name: "Free sample", price: ""}) |> render_submit()
    assert has_element?(lv, "#product-form [name='product[price]']")
    assert Delivest.Net.list_branch_products(branch.id) == []

    lv |> form("#product-form", product: %{name: "Free sample", price: "0"}) |> render_submit()
    assert %{price: 0, is_active: false} = Repo.get_by!(Delivest.Net.Product, name: "Free sample")

    {:ok, published, _} = live(conn, ~p"/staff/b/#{branch}/products/new")

    published
    |> form("#product-form", product: %{name: "Published", price: "1", is_active: true})
    |> render_submit()

    assert %{is_active: true} = Repo.get_by!(Delivest.Net.Product, name: "Published")
  end

  test "editing basic fields preserves category, rare fields, external ID and modifiers", %{
    conn: conn
  } do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    category = insert(:category)
    Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    product =
      insert_branch_product(branch.id,
        name: "Old",
        category_id: category.id,
        price: 100,
        calories: 32.5,
        excise: :sugary_drink,
        slug: "old"
      )

    group = Repo.insert!(%Delivest.Net.ModifierGroup{name: "Size", min: 0, max: 1})
    {:ok, _} = Delivest.Net.Modifiers.attach(staff, product.id, [group.id])

    Repo.insert!(%Delivest.Net.ProductExternalId{
      entity_id: product.id,
      branch_id: branch.id,
      provider: "frontpad",
      external_id: "REMOTE-1"
    })

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products/#{product.id}/edit")
    assert has_element?(lv, "#product-edit-page #product-dish-section")
    assert has_element?(lv, "#product-external-section")
    lv |> form("#product-form", product: %{name: "New", price: "100"}) |> render_submit()

    saved = Repo.get!(Delivest.Net.Product, product.id)
    assert saved.name == "New"
    assert saved.category_id == category.id
    assert saved.calories == 32.5
    assert saved.excise == :sugary_drink
    assert Delivest.Net.Modifiers.group_ids(product.id) == [group.id]

    assert Repo.get_by!(Delivest.Net.ProductExternalId, entity_id: product.id).external_id ==
             "REMOTE-1"
  end

  test "stale editor keeps a draft and cannot overwrite a newer product", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    product = insert_branch_product(branch.id, name: "Original", price: 100)
    path = ~p"/staff/b/#{branch}/products/#{product.id}/edit"

    {:ok, first, _} = live(conn, path)
    {:ok, second, _} = live(conn, path)

    first |> form("#product-form", product: %{name: "Saved first"}) |> render_submit()
    assert Repo.reload!(product).name == "Saved first"

    second |> form("#product-form", product: %{name: "Stale draft"}) |> render_submit()
    assert Repo.reload!(product).name == "Saved first"
    assert has_element?(second, "#product-save-error")
    assert has_element?(second, "#product-reload-latest")
    assert has_element?(second, "#product-form input[name='product[name]'][value='Stale draft']")

    second |> element("#product-reload-latest") |> render_click()
    assert has_element?(second, "#product-form input[name='product[name]'][value='Saved first']")
    refute has_element?(second, "#product-save-error")
  end

  test "external mapping changed after opening blocks a basic edit", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    product = insert_branch_product(branch.id, name: "Original")

    mapping =
      Repo.insert!(%Delivest.Net.ProductExternalId{
        entity_id: product.id,
        branch_id: branch.id,
        provider: "frontpad",
        external_id: "FIRST"
      })

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products/#{product.id}/edit")
    Repo.update!(Ecto.Changeset.change(mapping, external_id: "SECOND"))
    lv |> form("#product-form", product: %{name: "Draft"}) |> render_submit()

    assert has_element?(lv, "#product-reload-latest")
    assert Repo.reload!(product).name == "Original"
    assert Repo.reload!(mapping).external_id == "SECOND"
  end

  test "read-only staff opens a full product card and returns to filtered list", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    product = insert_branch_product(branch.id, name: "Read only", calories: 44.0)
    list = ~p"/staff/b/#{branch}/products?search=Read"

    {:ok, lv, _} = live(conn, list)
    assert has_element?(lv, "#products a", "Read only")
    lv |> element("#products a", "Read only") |> render_click()
    {show_url, _flash} = assert_redirect(lv)
    assert URI.parse(show_url).path == ~p"/staff/b/#{branch}/products/#{product.id}"
    {:ok, show, _} = live(conn, show_url)

    assert has_element?(
             show,
             "#product-edit-page #product-form.product-readonly-form fieldset[disabled]"
           )

    assert has_element?(show, "#product-dish-section")
    refute has_element?(show, "#product-edit-link")
    refute has_element?(show, "#product-form button[type=submit]")
    refute has_element?(show, "#product-form button[phx-click='open_upload_modal']")
    show |> element("#product-back-to-list") |> render_click()
    {return_url, _flash} = assert_redirect(show)
    assert URI.parse(return_url).fragment == "product-row-#{product.id}"

    assert return_url
           |> URI.parse()
           |> Map.fetch!(:query)
           |> URI.decode_query()
           |> Map.fetch!("search") == "Read"

    {:ok, back, _} = live(conn, return_url)
    assert has_element?(back, "#products a", "Read only")
  end

  test "CRM owned product rejects forged changes to name price and weight", %{conn: conn} do
    alias Delivest.Identity.Branch.BranchInfo
    alias Delivest.Integrations.Crm.BranchSettings
    alias Delivest.Integrations.Iiko

    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :iiko,
        menu_source: :crm,
        iiko: %Iiko.Settings{api_key: "test"}
      }
    })

    product = insert_branch_product(branch.id, name: "CRM name", price: 100, weight: 100)

    Repo.insert!(%Delivest.Net.ProductExternalId{
      entity_id: product.id,
      branch_id: branch.id,
      provider: "iiko",
      external_id: "CRM-1"
    })

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products/#{product.id}/edit")
    assert has_element?(lv, "#product-crm-owner")

    lv
    |> element("#product-form")
    |> render_submit(%{"product" => %{"name" => "Forged", "price" => "100", "weight" => "100"}})

    assert has_element?(lv, "#product-save-error")
    assert Repo.reload!(product).name == "CRM name"
  end

  test "product editor keeps draft after write permission is revoked", %{conn: conn} do
    branch = insert(:branch)
    role = insert(:role, permissions: ["products.read", "products.update"])
    staff = insert(:staff, role: role)
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    product = insert_branch_product(branch.id, name: "Original")

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products/#{product.id}/edit")
    Repo.update!(Ecto.Changeset.change(role, permissions: ["products.read"]))
    lv |> form("#product-form", product: %{name: "Denied draft"}) |> render_submit()

    assert has_element?(lv, "#product-save-error")
    assert has_element?(lv, "#product-form input[name='product[name]'][value='Denied draft']")
    assert Repo.reload!(product).name == "Original"
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

      lv |> element(~s(table thead th[data-column="name"] a)) |> render_click()
      first_sort_url = assert_patch(lv)
      assert String.contains?(first_sort_url, "order_by[]=name")
      assert String.contains?(first_sort_url, "order_directions[]=asc")
      assert length(product_row_ids(lv)) == 10
      assert product_first_name(lv) == "Match 1"

      lv |> element(~s(table thead th[data-column="name"] a)) |> render_click()
      second_sort_url = assert_patch(lv)
      assert String.contains?(second_sort_url, "order_directions[]=desc")
      assert length(product_row_ids(lv)) == 10
      assert product_first_name(lv) == "Match 9"
    end

    test "renders one local menu and page actions in main", %{
      conn: conn
    } do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")

      actions = render(element(lv, "#staff-page-header-actions"))

      assert has_element?(
               lv,
               "#staff-context-navigation #staff-section-navigation #product-section-tab-products[aria-current='page']"
             )

      assert Enum.count(
               LazyHTML.query(
                 LazyHTML.from_fragment(render(lv)),
                 "#staff-context-navigation #staff-section-navigation a"
               )
             ) == 7

      refute has_element?(lv, "#staff-header-context")
      assert has_element?(lv, "main #staff-page-header h1", "Products")
      assert has_element?(lv, "main #staff-page-header-actions")
      refute actions =~ ~s(id="copy-products-trigger")
      assert has_element?(lv, "#product-more-actions > summary", "More")
      assert has_element?(lv, "#product-more-actions #product-operations-link")
      assert has_element?(lv, "#product-more-actions #bulk-add-products")
      assert actions =~ ~s(id="product-operations-link")
      assert actions =~ ~s(id="bulk-add-products")
      assert actions =~ ~s(id="create-product")
      assert has_element?(lv, "main #products-filter")
      refute has_element?(lv, "main #products-filter [role='tablist']")
    end

    test "each product section selects one local entry", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      for {path, key, title, actions?} <- [
            {"", "products", "Products", true},
            {"/stops", "stops", "Stop list", false},
            {"/modifiers", "modifiers", "Modifiers", true},
            {"/tags", "tags", "Tags", true},
            {"/suggested", "suggested", "Recommended", true},
            {"/bulk", "products", "Bulk add products", true}
          ] do
        {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products" <> path)

        assert has_element?(
                 lv,
                 "#staff-context-navigation #staff-section-navigation #product-section-tab-#{key}[aria-current='page']"
               )

        for other <- ~w(products stops modifiers tags suggested) do
          assert has_element?(
                   lv,
                   "#staff-context-navigation #staff-section-navigation #product-section-tab-#{other}"
                 )

          if other != key,
            do:
              refute(
                has_element?(
                  lv,
                  "#staff-context-navigation #staff-section-navigation #product-section-tab-#{other}[aria-current='page']"
                )
              )
        end

        assert has_element?(lv, "main #staff-page-header h1", title)
        refute has_element?(lv, "#staff-header-context")

        if actions? do
          assert has_element?(lv, "main #staff-page-header-actions > *")
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

        assert has_element?(
                 lv,
                 "#staff-context-navigation #staff-section-navigation [aria-current='page']"
               )

        refute has_element?(lv, "#staff-page-header-actions > *")
      end
    end

    test "read-only staff sees product operations but no create actions", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")

      actions = render(element(lv, "#staff-page-header-actions"))
      assert has_element?(lv, "#product-more-actions #product-operations-link")
      assert actions =~ ~s(id="product-operations-link")
      refute actions =~ ~s(id="copy-products-trigger")
      refute actions =~ ~s(id="bulk-add-products")
      refute actions =~ ~s(id="create-product")
    end

    test "row menu keeps edit query and confirms deletion of the chosen product", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
      product = insert_branch_product(branch.id, name: "Menu target")

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products?search=Menu")
      edit = "#product-edit-#{product.id}"
      delete = "#product-delete-#{product.id}"
      assert has_element?(lv, "#{edit}[aria-label='Edit Menu target']")
      assert has_element?(lv, "#{delete}[aria-label='Delete Menu target']")

      lv |> element(edit) |> render_click()
      {edit_url, _flash} = assert_redirect(lv)
      assert URI.parse(edit_url).path == ~p"/staff/b/#{branch}/products/#{product.id}/edit"

      assert edit_url
             |> URI.parse()
             |> Map.fetch!(:query)
             |> URI.decode_query()
             |> Map.get("search") == "Menu"

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products?search=Menu")
      lv |> element(delete) |> render_click()
      assert has_element?(lv, "#delete-product-modal.modal-open", "Menu target")
      lv |> element("#delete-product-modal .modal-action button.btn-error") |> render_click()
      assert Repo.reload!(product).deleted_at != nil
    end

    test "read-only product rows do not expose edit or delete actions", %{conn: conn} do
      branch = insert(:branch)
      staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
      product = insert_branch_product(branch.id, name: "Read only")

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/products")
      refute has_element?(lv, "#product-row-more-#{product.id}")
      assert has_element?(lv, "#products a", "Read only")
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
    |> LazyHTML.query(~s(tbody#products tr:first-child td[data-column="name"]))
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

    matching_jobs =
      Enum.filter(Oban.Testing.all_enqueued(Delivest.Repo, []), fn job ->
        job.worker == "Delivest.Media.Workers.ThumbnailWorker" and
          job.args["file_id"] == media.id
      end)

    assert length(matching_jobs) == 1
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

      {:ok, lv, _html} =
        live(conn, ~p"/staff/b/#{branch}/products/operations?#{[ids: [chosen.id]]}")

      lv |> form("#copy-preview-form", %{"target_branch_id" => target.id}) |> render_submit()
      assert has_element?(lv, "#operations-preview")
      lv |> form("#operations-apply-form") |> render_submit()

      assert has_element?(lv, "#operations-result")
      assert [copy_id] = Delivest.Relations.list_target_ids("Branch", target.id, "Product")

      assert %{measure_unit: :ml, calories: 40.0, excise: :sugary_drink} =
               Delivest.Net.Products.get_product(copy_id)
    end

    test "copies every product of the branch", %{conn: conn, branch: branch, target: target} do
      insert_branch_product(branch.id, name: "One")
      insert_branch_product(branch.id, name: "Two")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/operations")
      lv |> form("#copy-preview-form", %{"target_branch_id" => target.id}) |> render_submit()
      lv |> form("#operations-apply-form") |> render_submit()

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
