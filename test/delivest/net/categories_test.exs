defmodule Delivest.Net.CategoriesTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net.Categories
  alias Delivest.Net.Category
  alias Delivest.Relations

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
  end

  describe "list_category_for_branch/2" do
    test "returns active categories ordered by order field for a branch" do
      branch = insert(:branch)
      cat1 = insert(:category, name: "First", order: 2.0, is_active: true)
      cat2 = insert(:category, name: "Second", order: 1.0, is_active: true)
      inactive_cat = insert(:category, name: "Inactive", order: 0.5, is_active: false)

      Relations.create_relation("Branch", branch.id, "Category", cat1.id)
      Relations.create_relation("Branch", branch.id, "Category", cat2.id)
      Relations.create_relation("Branch", branch.id, "Category", inactive_cat.id)

      result = Categories.list_category_for_branch(branch.id)

      assert length(result) == 2
      assert Enum.map(result, & &1.id) == [cat2.id, cat1.id]
    end
  end

  describe "list_staff_categories_for_branch/3" do
    test "returns all categories (including inactive) if staff has permission" do
      staff = staff_with_permissions(["categories.read"])
      branch = insert(:branch)
      cat1 = insert(:category, order: 1.0, is_active: true)
      cat2 = insert(:category, order: 2.0, is_active: false)

      Relations.create_relation("Branch", branch.id, "Category", cat1.id)
      Relations.create_relation("Branch", branch.id, "Category", cat2.id)

      result = Categories.list_staff_categories_for_branch(staff, branch.id)
      assert is_list(result)
      assert length(result) == 2
    end

    test "returns {:error, :forbidden} if staff lacks permission" do
      staff = staff_with_permissions(["some.other.permission"])
      branch = insert(:branch)

      assert {:error, :forbidden} = Categories.list_staff_categories_for_branch(staff, branch.id)
    end
  end

  describe "get_category/2" do
    test "returns {:ok, category} when category exists" do
      category = insert(:category)
      assert {:ok, fetched} = Categories.get_category(category.id)
      assert fetched.id == category.id
    end

    test "returns {:error, :not_found} when category does not exist" do
      non_existent_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Categories.get_category(non_existent_id)
    end
  end

  describe "create_category/3" do
    test "successfully creates category, calculates order and links to branch if permitted" do
      staff = staff_with_permissions(["categories.create"])
      branch = insert(:branch)

      existing_cat = insert(:category, order: 1.0)
      Relations.create_relation("Branch", branch.id, "Category", existing_cat.id)

      attrs = %{"name" => "New Category", "is_active" => true}

      assert {:ok, %Category{} = created} = Categories.create_category(staff, branch.id, attrs)
      assert created.name == "New Category"
      assert created.order == 2.0

      target_ids = Relations.list_target_ids("Branch", branch.id, "Category")
      assert created.id in target_ids
    end

    test "returns {:error, :forbidden} if staff lacks permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Categories.create_category(staff, branch.id, %{"name" => "Test"})
    end

    test "returns validation errors on invalid attributes" do
      staff = staff_with_permissions(["categories.create"])
      branch = insert(:branch)

      assert {:error, changeset} = Categories.create_category(staff, branch.id, %{"name" => nil})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "update_category/3" do
    test "successfully updates category if permitted and invalidates cache" do
      staff = staff_with_permissions(["categories.update"])
      category = insert(:category, name: "Old Name")
      branch = insert(:branch)
      Relations.create_relation("Branch", branch.id, "Category", category.id)

      assert {:ok, updated} =
               Categories.update_category(staff, category, %{"name" => "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "returns {:error, :forbidden} if staff lacks permission" do
      staff = staff_with_permissions([])
      category = insert(:category)

      assert {:error, :forbidden} =
               Categories.update_category(staff, category, %{"name" => "Test"})
    end
  end

  describe "delete_category/2" do
    test "successfully deletes category if permitted" do
      staff = staff_with_permissions(["categories.delete"])
      category = insert(:category)
      branch = insert(:branch)
      Relations.create_relation("Branch", branch.id, "Category", category.id)

      assert {:ok, deleted} = Categories.delete_category(staff, category)
      assert {:error, :not_found} = Categories.get_category(deleted.id)
    end

    test "returns {:error, :forbidden} if staff lacks permission" do
      staff = staff_with_permissions([])
      category = insert(:category)

      assert {:error, :forbidden} = Categories.delete_category(staff, category)
    end
  end

  describe "update_category_order/4" do
    test "calculates new order based on above and below orders correctly" do
      staff = staff_with_permissions(["categories.update"])
      category = insert(:category, order: 1.0)
      branch = insert(:branch)
      Relations.create_relation("Branch", branch.id, "Category", category.id)

      assert {:ok, updated} = Categories.update_category_order(staff, category, 1.0, 3.0)
      assert updated.order == 2.0
    end

    test "calculates order when above_order is nil" do
      staff = staff_with_permissions(["categories.update"])
      category = insert(:category)
      branch = insert(:branch)
      Relations.create_relation("Branch", branch.id, "Category", category.id)

      assert {:ok, updated} = Categories.update_category_order(staff, category, nil, 4.0)
      assert updated.order == 2.0
    end

    test "calculates order when below_order is nil" do
      staff = staff_with_permissions(["categories.update"])
      category = insert(:category)
      branch = insert(:branch)
      Relations.create_relation("Branch", branch.id, "Category", category.id)

      assert {:ok, updated} = Categories.update_category_order(staff, category, 5.0, nil)
      assert updated.order == 6.0
    end

    test "returns {:error, :forbidden} if staff lacks permission" do
      staff = staff_with_permissions([])
      category = insert(:category)

      assert {:error, :forbidden} = Categories.update_category_order(staff, category, 1.0, 2.0)
    end
  end
end
