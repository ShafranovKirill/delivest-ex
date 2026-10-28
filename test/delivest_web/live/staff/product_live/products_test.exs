defmodule DelivestWeb.Staff.ProductLive.ProductsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

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

      {:ok, _lv, html} = live(conn, ~p"/staff/products")

      assert html =~ "Products"
      assert html =~ "Create Product"
      assert html =~ "All categories"
      assert html =~ "All statuses"
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

    {:ok, lv, _html} = live(conn, ~p"/staff/products/new")
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

    {:ok, lv, html} = live(conn, ~p"/staff/products/new")
    assert html =~ "Острое"

    lv
    |> form("#product-form", product: %{name: "Том ям", price: 450, tags: ["", spicy.id, hit.id]})
    |> render_submit()

    {:ok, {[product], _meta}} =
      Delivest.Net.Products.list_staff_products_for_branch(staff, branch.id)

    assert Enum.sort(product.tags) == Enum.sort([hit.id, spicy.id])

    {:ok, lv, _html} = live(conn, ~p"/staff/products/#{product.id}/edit")
    lv |> form("#product-form", product: %{tags: [""]}) |> render_submit()

    assert %{tags: []} = Delivest.Net.Products.get_product(product.id)
  end

  test "nutrition and excise are saved with the product", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/products/new")

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

      {:ok, lv, _html} = live(conn, ~p"/staff/products")

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

      {:ok, lv, _html} = live(conn, ~p"/staff/products")
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
      {:ok, lv, _html} = live(conn, ~p"/staff/products")

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

      {:ok, _lv, html} = live(conn, ~p"/staff/products?stopped=true")

      assert html =~ "Soup"
      refute html =~ "Kompot"
      assert html =~ "Stop in Frontpad"
    end
  end
end
