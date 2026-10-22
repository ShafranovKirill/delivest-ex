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
      assert product_ids == [visible.id, inactive.id]
      refute deleted.id in product_ids
      refute unrelated.id in product_ids
    end

    test "returns forbidden without products.read permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)

      assert {:error, :forbidden} = Net.list_staff_products_for_branch(staff, branch.id)
    end
  end

  describe "create_product/3" do
    test "creates a product and links it to the branch" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)

      assert {:ok, %Product{} = product} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 250})

      assert product.name == "New"
      assert product.price == 250
      assert product.id in Relations.list_target_ids("Branch", branch.id, "Product")
    end

    test "returns validation errors for a negative price" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)

      assert {:error, changeset} =
               Net.create_product(staff, branch.id, %{"name" => "Bad", "price" => -1})

      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "returns forbidden without products.create permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 100})
    end
  end

  describe "update_product/3" do
    test "updates a product when permitted" do
      staff = staff_with_permissions(["products.update"])
      product = insert_product(%{name: "Old"})

      assert {:ok, updated} =
               Net.update_product(staff, product, %{"name" => "Updated", "price" => 125})

      assert updated.name == "Updated"
      assert updated.price == 125
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
end
