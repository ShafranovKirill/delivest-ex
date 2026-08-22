defmodule Delivest.Net.CategoriesTest do
  use Delivest.DataCase, async: false

  alias Delivest.Net.{Categories, Category}

  import Delivest.Factory

  setup do
    start_supervised!({Cachex, name: :menu_cache})

    admin_role =
      insert(:role,
        permissions: [
          "categories.read",
          "categories.create",
          "categories.update",
          "categories.delete"
        ]
      )

    read_only_staff = insert(:staff, role: insert(:role, permissions: ["categories.read"]))
    forbidden_staff = insert(:staff, role: insert(:role, permissions: []))
    admin = insert(:staff, role: admin_role)
    branch = insert(:branch)

    {:ok,
     admin: admin,
     read_only_staff: read_only_staff,
     forbidden_staff: forbidden_staff,
     branch: branch}
  end

  describe "list_category_for_branch/2" do
    test "returns categories for the branch ordered by order", %{branch: branch} do
      first = insert(:category, branch: branch, order: 2.0)
      second = insert(:category, branch: branch, order: 1.0)
      insert(:category, branch: insert(:branch), order: 0.0)

      assert [%Category{id: second_id, order: 1.0}, %Category{id: first_id, order: 2.0}] =
               Categories.list_category_for_branch(branch.id)

      assert second_id == second.id
      assert first_id == first.id
    end

    test "preloads requested associations", %{branch: branch} do
      category = insert(:category, branch: branch, order: 1.0)

      assert [%Category{branch: %Delivest.Net.Branch{id: branch_id}}] =
               Categories.list_category_for_branch(branch.id, preload: :branch)

      assert branch_id == branch.id
      assert category.id == hd(Categories.list_category_for_branch(branch.id)).id
    end
  end

  describe "list_staff_categories_for_branch/3" do
    test "returns categories for staff with permission", %{read_only_staff: staff, branch: branch} do
      category = insert(:category, branch: branch, order: 1.0)

      assert [%Category{id: category_id, name: category_name, order: 1.0}] =
               Categories.list_staff_categories_for_branch(staff, branch.id)

      assert category_id == category.id
      assert category_name == category.name
    end

    test "returns forbidden without categories.read permission", %{
      forbidden_staff: staff,
      branch: branch
    } do
      assert {:error, :forbidden} = Categories.list_staff_categories_for_branch(staff, branch.id)
    end
  end

  describe "get_category/2" do
    test "returns a category and preloads requested associations", %{branch: branch} do
      category = insert(:category, branch: branch, order: 1.0)

      assert {:ok, %Category{id: id, branch: %Delivest.Net.Branch{id: branch_id}}} =
               Categories.get_category(category.id, preload: :branch)

      assert id == category.id
      assert branch_id == branch.id
    end

    test "returns not found for an unknown id" do
      assert {:error, :not_found} = Categories.get_category(Ecto.UUID.generate())
    end
  end

  describe "create_category/3" do
    test "creates a category with the next order and clears the menu cache", %{
      admin: admin,
      branch: branch
    } do
      insert(:category, branch: branch, order: 3.5)
      Cachex.put(:menu_cache, branch.id, :cached_menu)

      assert {:ok, %Category{name: "Drinks", order: 4.5, branch_id: branch_id}} =
               Categories.create_category(admin, branch.id, %{"name" => "Drinks"})

      assert branch_id == branch.id
      assert {:ok, nil} = Cachex.get(:menu_cache, branch.id)
    end

    test "starts the order at one for the first category", %{admin: admin, branch: branch} do
      assert {:ok, %Category{order: 1.0}} =
               Categories.create_category(admin, branch.id, %{"name" => "Food"})
    end

    test "returns changeset errors for invalid data", %{admin: admin, branch: branch} do
      assert {:error, changeset} = Categories.create_category(admin, branch.id, %{"name" => ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns forbidden without categories.create permission", %{
      read_only_staff: staff,
      branch: branch
    } do
      assert {:error, :forbidden} =
               Categories.create_category(staff, branch.id, %{"name" => "Food"})
    end
  end

  describe "update_category/3" do
    test "updates a category and clears the menu cache", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, name: "Food", order: 1.0)
      Cachex.put(:menu_cache, branch.id, :cached_menu)

      assert {:ok, %Category{name: "Drinks"}} =
               Categories.update_category(admin, category, %{"name" => "Drinks"})

      assert {:ok, nil} = Cachex.get(:menu_cache, branch.id)
    end

    test "returns forbidden without categories.update permission", %{
      read_only_staff: staff,
      branch: branch
    } do
      category = insert(:category, branch: branch, order: 1.0)

      assert {:error, :forbidden} = Categories.update_category(staff, category, %{name: "Food"})
    end
  end

  describe "delete_category/2" do
    test "deletes a category and clears the menu cache", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 1.0)
      Cachex.put(:menu_cache, branch.id, :cached_menu)

      assert {:ok, %Category{id: id}} = Categories.delete_category(admin, category)
      assert Repo.get(Category, id) == nil
      assert {:ok, nil} = Cachex.get(:menu_cache, branch.id)
    end

    test "returns forbidden without categories.delete permission", %{
      read_only_staff: staff,
      branch: branch
    } do
      category = insert(:category, branch: branch, order: 1.0)

      assert {:error, :forbidden} = Categories.delete_category(staff, category)
    end
  end

  describe "update_category_order/4" do
    test "places a category between neighboring categories", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 10.0)
      Cachex.put(:menu_cache, branch.id, :cached_menu)

      assert {:ok, %Category{order: 3.0}} =
               Categories.update_category_order(admin, category, 2.0, 4.0)

      assert {:ok, nil} = Cachex.get(:menu_cache, branch.id)
    end

    test "places a category before a positive first category", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 10.0)

      assert {:ok, %Category{order: 2.0}} =
               Categories.update_category_order(admin, category, nil, 4.0)
    end

    test "places a category before a non-positive first category", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 10.0)

      assert {:ok, %Category{order: -2.0}} =
               Categories.update_category_order(admin, category, nil, -1.0)
    end

    test "places a category after the last category", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 1.0)

      assert {:ok, %Category{order: 6.0}} =
               Categories.update_category_order(admin, category, 5.0, nil)
    end

    test "uses one when no neighbors are provided", %{admin: admin, branch: branch} do
      category = insert(:category, branch: branch, order: 10.0)

      assert {:ok, %Category{order: 1.0}} =
               Categories.update_category_order(admin, category, nil, nil)
    end

    test "returns forbidden without categories.update permission", %{
      read_only_staff: staff,
      branch: branch
    } do
      category = insert(:category, branch: branch, order: 1.0)

      assert {:error, :forbidden} =
               Categories.update_category_order(staff, category, nil, nil)
    end
  end
end
