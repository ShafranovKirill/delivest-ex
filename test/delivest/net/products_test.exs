defmodule Delivest.Net.ProductsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net
  alias Delivest.Net.Product
  alias Delivest.Relations

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
  end

  defp grant_product_branch(staff, product) do
    branch = insert(:branch)
    Relations.create_relation(Delivest.Repo, "Branch", branch.id, "Product", product.id, %{})
    insert(:staff_branch, staff: staff, branch: branch)
  end

  defp insert_product(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Product", price: 100, is_active: true}, attrs)

    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert!()
  end

  describe "list_staff_products_for_branch/4" do
    test "returns non-deleted products linked to the branch" do
      staff = staff_with_permissions(["products.read"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      visible = insert_product(%{name: "Visible"})
      inactive = insert_product(%{name: "Inactive", is_active: false})
      deleted = insert_product(%{name: "Deleted", deleted_at: DateTime.utc_now(:second)})
      unrelated = insert_product(%{name: "Unrelated"})

      for product <- [visible, inactive, deleted] do
        assert {:ok, _} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, {products, _meta}} = Net.list_staff_products_for_branch(staff, branch.id)
      product_ids = Enum.map(products, & &1.id)
      assert Enum.sort(product_ids) == Enum.sort([visible.id, inactive.id])
      refute deleted.id in product_ids
      refute unrelated.id in product_ids
    end

    test "returns forbidden without products.read permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, :forbidden} = Net.list_staff_products_for_branch(staff, branch.id)
    end
  end

  describe "create_product/3" do
    test "creates a product and links it to the branch" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:ok, %Product{} = product} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 250})

      assert product.name == "New"
      assert product.price == 250
      assert product.id in Relations.list_target_ids("Branch", branch.id, "Product")
    end

    test "returns validation errors for a negative price" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, changeset} =
               Net.create_product(staff, branch.id, %{"name" => "Bad", "price" => -1})

      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "returns forbidden without products.create permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, :forbidden} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 100})
    end
  end

  describe "update_product/3" do
    test "updates a product when permitted" do
      staff = staff_with_permissions(["products.update"])
      product = insert_product(%{name: "Old"})
      grant_product_branch(staff, product)

      assert {:ok, updated} =
               Net.update_product(staff, product, %{"name" => "Updated", "price" => 125})

      assert updated.name == "Updated"
      assert updated.price == 125
    end

    test "an editor of another branch cannot change the product" do
      staff = staff_with_permissions(["products.update", "products.delete"])
      product = insert_product()
      grant_product_branch(staff_with_permissions([]), product)
      insert(:staff_branch, staff: staff, branch: insert(:branch))

      assert {:error, :forbidden} = Net.update_product(staff, product, %{"name" => "X"})
      assert {:error, :forbidden} = Net.soft_delete_product(staff, product)
    end

    test "returns forbidden without products.update permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} =
               Net.update_product(staff, product, %{"name" => "Updated"})
    end
  end

  describe "soft_delete_product/2" do
    test "sets deleted_at when permitted" do
      staff = staff_with_permissions(["products.delete"])
      product = insert_product()
      grant_product_branch(staff, product)

      assert {:ok, deleted} = Net.soft_delete_product(staff, product)
      assert %DateTime{} = deleted.deleted_at
    end

    test "returns forbidden without products.delete permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} = Net.soft_delete_product(staff, product)
    end
  end

  describe "soft_delete_products/3" do
    test "deletes only selected products of the branch" do
      staff = staff_with_permissions(["products.delete"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      selected = insert_product(%{name: "Selected"})
      kept = insert_product(%{name: "Kept"})
      foreign = insert_product(%{name: "Foreign"})

      for product <- [selected, kept] do
        assert {:ok, _} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, [deleted]} =
               Net.soft_delete_products(staff, branch.id, [selected.id, foreign.id])

      assert deleted.id == selected.id
      assert %DateTime{} = Repo.get!(Product, selected.id).deleted_at
      assert is_nil(Repo.get!(Product, kept.id).deleted_at)
      assert is_nil(Repo.get!(Product, foreign.id).deleted_at)
    end

    test "returns forbidden without products.delete permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      product = insert_product()

      assert {:error, :forbidden} = Net.soft_delete_products(staff, branch.id, [product.id])
    end
  end

  describe "product order" do
    defp branch_product(branch, attrs) do
      product = insert(:product, attrs)

      assert {:ok, _} =
               Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)

      product
    end

    test "new products go to the end of their category" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      category = insert(:category)

      assert {:ok, first} =
               Net.create_product(staff, branch.id, %{
                 "name" => "B",
                 "price" => 1,
                 "category_id" => category.id
               })

      assert {:ok, second} =
               Net.create_product(staff, branch.id, %{
                 "name" => "A",
                 "price" => 1,
                 "category_id" => category.id
               })

      assert second.order > first.order

      assert Enum.map(Net.list_category_products(branch.id, category.id), & &1.id) ==
               [first.id, second.id]
    end

    test "moving to another category puts the product at its end" do
      staff = staff_with_permissions(["products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      from = insert(:category)
      to = insert(:category)
      product = branch_product(branch, %{name: "Moved", category_id: from.id, order: 1.0})
      branch_product(branch, %{name: "There", category_id: to.id, order: 5.0})

      assert {:ok, moved} = Net.update_product(staff, product, %{"category_id" => to.id})
      assert moved.order == 6.0
    end

    test "update_product_order places the product between its neighbours" do
      staff = staff_with_permissions(["products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      category = insert(:category)
      a = branch_product(branch, %{name: "A", category_id: category.id, order: 1.0})
      b = branch_product(branch, %{name: "B", category_id: category.id, order: 2.0})
      c = branch_product(branch, %{name: "C", category_id: category.id, order: 3.0})

      assert {:ok, _} = Net.update_product_order(staff, c, a.order, b.order)

      assert Enum.map(Net.list_category_products(branch.id, category.id), & &1.id) ==
               [a.id, c.id, b.id]
    end

    test "update_product_order requires products.update" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} = Net.update_product_order(staff, product, nil, nil)
    end
  end

  describe "crm ids" do
    alias Delivest.Net.ProductCrmIds

    setup do
      staff = staff_with_permissions(["products.create", "products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      %{staff: staff, branch: branch}
    end

    defp crm_ids(product),
      do: product.id |> List.wrap() |> ProductCrmIds.by_product(:frontpad)

    test "are stored per provider and updated in place", %{staff: staff, branch: branch} do
      {:ok, product} =
        Net.create_product(staff, branch.id, %{
          "name" => "Soup",
          "price" => 100,
          "crm_ids" => %{"frontpad" => " 101 "}
        })

      assert crm_ids(product) == %{product.id => "101"}

      {:ok, product} = Net.update_product(staff, product, %{"crm_ids" => %{"frontpad" => "102"}})
      assert crm_ids(product) == %{product.id => "102"}

      {:ok, product} = Net.update_product(staff, product, %{"name" => "Borsch"})
      assert crm_ids(product) == %{product.id => "102"}

      {:ok, product} = Net.update_product(staff, product, %{"crm_ids" => %{"frontpad" => ""}})
      assert crm_ids(product) == %{}
    end

    test "cannot repeat inside a branch but can across branches", %{staff: staff, branch: branch} do
      attrs = %{"name" => "Soup", "price" => 100, "crm_ids" => %{"frontpad" => "7"}}

      {:ok, _first} = Net.create_product(staff, branch.id, attrs)
      assert {:error, changeset} = Net.create_product(staff, branch.id, attrs)
      assert %{crm_ids: [_message]} = errors_on(changeset)

      other = insert(:branch)
      insert(:staff_branch, staff: staff, branch: other)
      assert {:ok, _other} = Net.create_product(staff, other.id, attrs)
    end
  end
end
