defmodule DelivestWeb.Staff.CategoryLive.CategoriesTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Net, Relations, Repo}

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    category = insert(:category, name: "Pizza")
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch, category: category}
  end

  defp branch_product(branch, attrs) do
    product = insert(:product, attrs)
    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    product
  end

  test "drag in the products panel changes the menu order", %{
    conn: conn,
    branch: branch,
    category: category
  } do
    a = branch_product(branch, %{name: "Margherita", category_id: category.id, order: 1.0})
    b = branch_product(branch, %{name: "Pepperoni", category_id: category.id, order: 2.0})
    c = branch_product(branch, %{name: "Hawaii", category_id: category.id, order: 3.0})

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/categories/#{category.id}/products")

    assert html =~ "Margherita"
    assert html =~ "Hawaii"

    lv
    |> element("#category-products-#{category.id}")
    |> render_hook("reorder_product", %{
      "id" => c.id,
      "above_order" => nil,
      "below_order" => a.order
    })

    assert Enum.map(Net.list_category_products(branch.id, category.id), & &1.id) ==
             [c.id, a.id, b.id]
  end

  test "products of another category cannot be reordered from the panel", %{
    conn: conn,
    branch: branch,
    category: category
  } do
    other = insert(:category)
    foreign = branch_product(branch, %{name: "Cola", category_id: other.id, order: 1.0})
    branch_product(branch, %{name: "Margherita", category_id: category.id, order: 1.0})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/categories/#{category.id}/products")

    lv
    |> element("#category-products-#{category.id}")
    |> render_hook("reorder_product", %{
      "id" => foreign.id,
      "above_order" => 5.0,
      "below_order" => nil
    })

    assert Repo.reload!(foreign).order == 1.0
  end
end
