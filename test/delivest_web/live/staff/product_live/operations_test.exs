defmodule DelivestWeb.Staff.ProductLive.OperationsTest do
  use DelivestWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Features

  test "staff previews and copies to another branch", %{conn: conn} do
    source = insert(:branch)
    target = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert_branch_product(source.id, name: "Tea")
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => source.id})
    {:ok, view, _html} = live(conn, ~p"/staff/b/#{source}/products/operations")
    assert has_element?(view, "#staff-page-header", "Товарные операции")
    assert has_element?(view, "#sidebar-group-menu[open] #sidebar-product-section-tab-products")
    refute has_element?(view, "#staff-header[data-header-layout='product-tabs']")
    assert has_element?(view, "#workbook-export")
    assert has_element?(view, "#workbook-upload-form")
    assert has_element?(view, "#copy-preview-form")
    view |> form("#copy-preview-form", %{"target_branch_id" => target.id}) |> render_submit()
    assert has_element?(view, "#operations-preview")
    view |> form("#operations-apply-form") |> render_submit()
    assert has_element?(view, "#operations-result")
    assert length(Delivest.Relations.list_target_ids("Branch", target.id, "Product")) == 1
  end

  test "back link returns to the same filtered products page", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, view, _} =
      live(
        conn,
        ~p"/staff/b/#{branch}/products/operations?search=Soup&page=2&page_size=10&stopped=true&ids[]=fake"
      )

    [target] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#product-operations-back")
      |> LazyHTML.attribute("href")

    assert URI.parse(target).path == ~p"/staff/b/#{branch}/products"

    assert URI.decode_query(URI.parse(target).query) == %{
             "search" => "Soup",
             "page" => "2",
             "page_size" => "10",
             "stopped" => "true"
           }
  end

  test "staff uploads workbook and chooses update on a matched row", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    row =
      Map.new(Delivest.Net.ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "coffee[M]",
        "name" => "Tea",
        "price_rub" => "2,50",
        "measure_unit" => "g",
        "is_active" => "true",
        "suggested" => "false"
      })

    {:ok, binary} = Delivest.Net.ProductWorkbook.encode([row])
    {:ok, view, _html} = live(conn, ~p"/staff/b/#{branch}/products/operations")

    upload =
      file_input(view, "#workbook-upload-form", :workbook, [
        %{
          name: "products.xlsx",
          content: binary,
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    assert render_upload(upload, "products.xlsx") =~ "100%"
    view |> form("#workbook-upload-form") |> render_submit()
    assert has_element?(view, "#operation-row-2")
    view |> form("#operations-apply-form") |> render_submit()
    assert has_element?(view, "#operations-result")

    upload =
      file_input(view, "#workbook-upload-form", :workbook, [
        %{
          name: "products.xlsx",
          content: binary,
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    render_upload(upload, "products.xlsx")
    view |> form("#workbook-upload-form") |> render_submit()
    assert has_element?(view, ~s(#operation-row-2 select option[value="update"]))

    view
    |> form("#operations-apply-form", %{"choices" => %{"2" => "update"}})
    |> render_submit()

    assert has_element?(view, "#operations-result")
    render_click(view, "apply")
    assert has_element?(view, "#operations-error")
    assert length(Delivest.Relations.list_target_ids("Branch", branch.id, "Product")) == 1
  end

  test "import controls and an open import preview disappear when the capability is disabled", %{
    conn: conn
  } do
    branch = insert(:branch)
    target = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    insert_branch_product(branch.id, name: "Copy source")
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    row =
      Map.new(Delivest.Net.ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "upload-1",
        "name" => "Imported",
        "price_rub" => "1,25",
        "measure_unit" => "g",
        "is_active" => "true",
        "suggested" => "false"
      })

    {:ok, binary} = Delivest.Net.ProductWorkbook.encode([row])
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/products/operations")
    assert has_element?(view, "#workbook-import")

    upload =
      file_input(view, "#workbook-upload-form", :workbook, [
        %{
          name: "products.xlsx",
          content: binary,
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    render_upload(upload, "products.xlsx")
    view |> form("#workbook-upload-form") |> render_submit()
    assert has_element?(view, "#operations-preview")

    {:ok, _} = Features.configure("product_import", {:branch, branch.id}, false, actor: "test")
    Phoenix.PubSub.broadcast(Delivest.PubSub, "features:changed", :features_changed)
    refute has_element?(view, "#workbook-import")
    refute has_element?(view, "#operations-preview")
    assert has_element?(view, "#workbook-export")
    assert has_element?(view, "#copy-preview-form")

    view |> form("#copy-preview-form", %{"target_branch_id" => target.id}) |> render_submit()
    assert has_element?(view, "#operations-preview")
    view |> form("#operations-apply-form") |> render_submit()
    assert has_element?(view, "#operations-result")

    {:ok, _} = Features.configure("product_import", {:branch, branch.id}, true, actor: "test")
    Phoenix.PubSub.broadcast(Delivest.PubSub, "features:changed", :features_changed)
    assert has_element?(view, "#workbook-import")
  end
end
