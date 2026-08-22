defmodule Delivest.Net.CategoriesTest do
  use Delivest.DataCase, async: true

  alias Delivest.Net.{Categories, Category}
  import Delivest.Factory

  setup do
    start_supervised({Cachex, name: :menu_cache})
    Cachex.clear(:menu_cache)

    admin_role =
      insert(:role,
        permissions: [
          "categories.read",
          "categories.create",
          "categories.update",
          "categories.delete"
        ]
      )

    read_only_role = insert(:role, permissions: ["categories.read"])
    forbidden_role = insert(:role, permissions: [])

    {:ok,
     admin: insert(:staff, role: admin_role),
     read_only_staff: insert(:staff, role: read_only_role),
     forbidden_staff: insert(:staff, role: forbidden_role)}
  end

  defp category_attrs(branch_ids, name \\ "Drinks") do
    %{name: name, branch_ids: branch_ids}
  end

  describe "list_category_for_branch/2" do
    test "returns active categories for a branch", %{} do
      branch = insert(:branch)
      active = insert(:category, name: "Active", is_active: true)
      inactive = insert(:category, name: "Inactive", is_active: false)

      Repo.insert!(%Delivest.Net.CategoriesBranches{
        category_id: active.id,
        branch_id: branch.id,
        order: 1.0
      })

      Repo.insert!(%Delivest.Net.CategoriesBranches{
        category_id: inactive.id,
        branch_id: branch.id,
        order: 2.0
      })

      categories = Categories.list_category_for_branch(branch.id)

      assert Enum.map(categories, & &1.id) == [active.id]
      refute inactive.id in Enum.map(categories, & &1.id)
    end

    test "preloads branches when requested", %{admin: admin} do
      branch = insert(:branch)
      {:ok, category} = Categories.create_category(admin, category_attrs([branch.id]))
      Repo.update_all(from(c in Category, where: c.id == ^category.id), set: [is_active: true])

      [loaded_category] = Categories.list_category_for_branch(branch.id, preload: [:branches])

      [loaded_branch] = loaded_category.branches
      branch_id = loaded_branch.id
      assert branch_id == branch.id
    end
  end

  describe "list_staff_categories_for_branch/3" do
    test "returns categories, including inactive ones, for permitted staff", %{
      read_only_staff: staff
    } do
      branch = insert(:branch)
      category = insert(:category, name: "Hidden")

      Repo.insert!(%Delivest.Net.CategoriesBranches{
        category_id: category.id,
        branch_id: branch.id
      })

      assert [%Category{id: category_id}] =
               Categories.list_staff_categories_for_branch(staff, branch.id)

      assert category_id == category.id
    end

    test "returns forbidden for staff without permission", %{forbidden_staff: staff} do
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Categories.list_staff_categories_for_branch(staff, branch.id)
    end
  end

  describe "get_category/2" do
    test "returns a category and preloads requested associations" do
      branch = insert(:branch)
      category = insert(:category)

      Repo.insert!(%Delivest.Net.CategoriesBranches{
        category_id: category.id,
        branch_id: branch.id
      })

      assert {:ok, loaded_category} = Categories.get_category(category.id, preload: [:branches])
      assert [%{id: branch_id}] = loaded_category.branches
      assert branch_id == branch.id
    end

    test "returns not found for an unknown id" do
      assert {:error, :not_found} = Categories.get_category(Ecto.UUID.generate())
    end
  end

  describe "create_category/2" do
    test "creates a category with branches when permitted", %{admin: admin} do
      branch = insert(:branch)

      assert {:ok, %Category{name: "Desserts", branches: [%{id: branch_id}]}} =
               Categories.create_category(admin, category_attrs([branch.id], "Desserts"))

      assert branch_id == branch.id
    end

    test "returns forbidden when staff lacks permission", %{forbidden_staff: staff} do
      assert {:error, :forbidden} = Categories.create_category(staff, %{name: "Desserts"})
    end
  end

  describe "update_category/3" do
    test "updates the category and its branches", %{admin: admin} do
      old_branch = insert(:branch)
      new_branch = insert(:branch)
      {:ok, category} = Categories.create_category(admin, category_attrs([old_branch.id]))

      assert {:ok, updated} =
               Categories.update_category(
                 admin,
                 category,
                 category_attrs([new_branch.id], "Food")
               )

      assert updated.name == "Food"
      assert Enum.map(updated.branches, & &1.id) == [new_branch.id]
      refute old_branch.id in Enum.map(updated.branches, & &1.id)
    end

    test "returns forbidden when staff lacks permission", %{forbidden_staff: staff} do
      category = insert(:category)

      assert {:error, :forbidden} = Categories.update_category(staff, category, %{name: "Food"})
    end
  end

  describe "soft_delete_category/2" do
    test "deletes the category when permitted", %{admin: admin} do
      category = insert(:category)

      assert {:ok, %Category{id: category_id}} = Categories.soft_delete_category(admin, category)
      assert Repo.get(Category, category_id) == nil
    end

    test "returns forbidden when staff lacks permission", %{forbidden_staff: staff} do
      category = insert(:category)

      assert {:error, :forbidden} = Categories.soft_delete_category(staff, category)
    end
  end
end
