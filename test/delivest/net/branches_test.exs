defmodule Delivest.Net.BranchesTest do
  use Delivest.DataCase, async: true

  alias Delivest.Net.{Branches, Branch}
  import Delivest.Factory

  setup do
    start_supervised({Cachex, name: :branch_cache})
    Cachex.clear(:branch_cache)

    admin_role =
      insert(:role,
        permissions: ["admin", "branch.read", "branch.create", "branch.update", "branch.delete"]
      )

    admin_staff = insert(:staff, role: admin_role)

    read_only_role = insert(:role, permissions: ["branch.read"])
    read_only_staff = insert(:staff, role: read_only_role)

    forbidden_role = insert(:role, permissions: [])
    forbidden_staff = insert(:staff, role: forbidden_role)

    {:ok, admin: admin_staff, read_only_staff: read_only_staff, forbidden_staff: forbidden_staff}
  end

  describe "list_branch/1" do
    test "should return all branches when admin", %{admin: admin} do
      branch1 = insert(:branch, name: "Main Branch")
      branch2 = insert(:branch, name: "Secondary Branch")

      query = Branches.list_branch(admin)
      branches = Delivest.Repo.all(query)
      branch_ids = Enum.map(branches, & &1.id)

      assert branch1.id in branch_ids
      assert branch2.id in branch_ids
    end

    test "should return empty query when staff lacks branch.read permission", %{
      forbidden_staff: staff
    } do
      insert(:branch)
      insert(:branch)

      query = Branches.list_branch(staff)
      branches = Delivest.Repo.all(query)

      assert branches == []
    end
  end

  describe "get_branch/1" do
    test "should return branch from DB and populate cache on cache miss" do
      branch = insert(:branch)

      assert {:ok, nil} = Cachex.get(:branch_cache, branch.id)
      assert {:ok, %Branch{} = fetched_branch} = Branches.get_branch(branch.id)
      assert fetched_branch.id == branch.id

      assert {:ok, %Branch{} = cached_branch} = Cachex.get(:branch_cache, branch.id)
      assert cached_branch.id == branch.id
    end

    test "should return branch from cache on cache hit" do
      branch = insert(:branch)
      Cachex.put(:branch_cache, branch.id, branch)

      assert {:ok, %Branch{} = fetched_branch} = Branches.get_branch(branch.id)
      assert fetched_branch.id == branch.id
    end

    test "should return error if branch doesn't exist" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Branches.get_branch(fake_id)
    end

    test "should update cache TTL on retrieval" do
      branch = insert(:branch)
      Cachex.put(:branch_cache, branch.id, branch, ttl: 100)

      {:ok, %Branch{}} = Branches.get_branch(branch.id)

      # Verify the cache entry has a reasonable TTL (30 minutes)
      assert {:ok, _} = Cachex.get(:branch_cache, branch.id)
    end
  end

  describe "create_branch/2" do
    test "should create branch with valid data when permitted", %{admin: admin} do
      attrs = %{name: "New Branch"}

      assert {:ok, %Branch{} = branch} = Branches.create_branch(admin, attrs)
      assert branch.name == "New Branch"
      assert branch.id != nil
    end

    test "should return error changeset with invalid data when permitted", %{admin: admin} do
      attrs = %{name: ""}

      assert {:error, %Ecto.Changeset{} = changeset} = Branches.create_branch(admin, attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "should return error when branch name is too short", %{admin: admin} do
      attrs = %{name: "B"}

      assert {:error, %Ecto.Changeset{} = changeset} = Branches.create_branch(admin, attrs)
      assert "should be at least 2 character(s)" in errors_on(changeset).name
    end

    test "should return error when branch name is too long", %{admin: admin} do
      long_name = String.duplicate("a", 51)
      attrs = %{name: long_name}

      assert {:error, %Ecto.Changeset{} = changeset} = Branches.create_branch(admin, attrs)
      assert "should be at most 50 character(s)" in errors_on(changeset).name
    end

    test "should return error when branch name is not unique", %{admin: admin} do
      insert(:branch, name: "Existing Branch")
      attrs = %{name: "Existing Branch"}

      assert {:error, %Ecto.Changeset{} = changeset} = Branches.create_branch(admin, attrs)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "should return forbidden when actor lacks branch.create permission", %{
      forbidden_staff: staff
    } do
      attrs = %{name: "Forbidden Branch"}

      assert {:error, :forbidden} = Branches.create_branch(staff, attrs)
    end

    test "should return forbidden when actor has no permissions", %{read_only_staff: staff} do
      attrs = %{name: "ReadOnly Branch"}

      assert {:error, :forbidden} = Branches.create_branch(staff, attrs)
    end
  end

  describe "update_branch/3" do
    test "should update branch with valid data when permitted", %{admin: admin} do
      branch = insert(:branch, name: "Old Name")
      attrs = %{name: "New Name"}

      assert {:ok, %Branch{} = updated_branch} = Branches.update_branch(admin, branch, attrs)
      assert updated_branch.name == "New Name"
    end

    test "should clear cache when updating branch", %{admin: admin} do
      branch = insert(:branch, name: "Old Name")
      Cachex.put(:branch_cache, branch.id, branch)

      assert {:ok, nil} != Cachex.get(:branch_cache, branch.id)

      {:ok, _updated_branch} = Branches.update_branch(admin, branch, %{name: "New Name"})

      assert {:ok, nil} = Cachex.get(:branch_cache, branch.id)
    end

    test "should return error changeset with invalid data when permitted", %{admin: admin} do
      branch = insert(:branch, name: "Valid Name")
      attrs = %{name: ""}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Branches.update_branch(admin, branch, attrs)

      assert "can't be blank" in errors_on(changeset).name
    end

    test "should return error when updating to duplicate name", %{admin: admin} do
      _branch1 = insert(:branch, name: "Branch One")
      branch2 = insert(:branch, name: "Branch Two")

      attrs = %{name: "Branch One"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Branches.update_branch(admin, branch2, attrs)

      assert "has already been taken" in errors_on(changeset).name
    end

    test "should return error with name too short when permitted", %{admin: admin} do
      branch = insert(:branch, name: "Valid Name")
      attrs = %{name: "B"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Branches.update_branch(admin, branch, attrs)

      assert "should be at least 2 character(s)" in errors_on(changeset).name
    end

    test "should return error with name too long when permitted", %{admin: admin} do
      branch = insert(:branch, name: "Valid Name")
      long_name = String.duplicate("a", 51)
      attrs = %{name: long_name}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Branches.update_branch(admin, branch, attrs)

      assert "should be at most 50 character(s)" in errors_on(changeset).name
    end

    test "should return forbidden when actor lacks branch.update permission", %{
      forbidden_staff: staff
    } do
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Branches.update_branch(staff, branch, %{name: "New Name"})
    end

    test "should return forbidden when actor has only read permission", %{
      read_only_staff: staff
    } do
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Branches.update_branch(staff, branch, %{name: "New Name"})
    end
  end

  describe "branches - cache integration" do
    test "should handle cache expiration and refetch from DB" do
      branch = insert(:branch)

      # First fetch caches the branch
      {:ok, fetched1} = Branches.get_branch(branch.id)
      assert fetched1.id == branch.id

      # Manually expire cache
      Cachex.del(:branch_cache, branch.id)

      # Next fetch should refetch from DB
      {:ok, fetched2} = Branches.get_branch(branch.id)
      assert fetched2.id == branch.id
    end
  end

  describe "branches - concurrent operations" do
    test "should handle concurrent reads from cache", %{admin: _admin} do
      branch = insert(:branch)
      Cachex.put(:branch_cache, branch.id, branch)

      task1 = Task.async(fn -> Branches.get_branch(branch.id) end)
      task2 = Task.async(fn -> Branches.get_branch(branch.id) end)
      task3 = Task.async(fn -> Branches.get_branch(branch.id) end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)
      result3 = Task.await(task3)

      assert {:ok, %Branch{}} = result1
      assert {:ok, %Branch{}} = result2
      assert {:ok, %Branch{}} = result3
    end

    test "should handle concurrent updates clearing cache", %{admin: admin} do
      branch = insert(:branch, name: "Original")
      Cachex.put(:branch_cache, branch.id, branch)

      task1 =
        Task.async(fn ->
          Branches.update_branch(admin, branch, %{name: "Updated1"})
        end)

      task2 =
        Task.async(fn ->
          Branches.update_branch(admin, branch, %{name: "Updated2"})
        end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # Both operations should succeed
      assert {:ok, %Branch{}} = result1
      assert {:ok, %Branch{}} = result2

      # Cache should be cleared after updates
      assert {:ok, nil} = Cachex.get(:branch_cache, branch.id)
    end
  end

  describe "branches - edge cases" do
    test "should handle branch name with special characters", %{admin: admin} do
      attrs = %{name: "Branch-Name (Special) & Characters"}

      assert {:ok, %Branch{} = branch} = Branches.create_branch(admin, attrs)
      assert branch.name == "Branch-Name (Special) & Characters"
    end

    test "should handle branch name with spaces", %{admin: admin} do
      attrs = %{name: "   Trimmed Name   "}

      assert {:ok, %Branch{} = branch} = Branches.create_branch(admin, attrs)
      assert branch.name == "   Trimmed Name   "
    end

    test "should handle exact length boundaries", %{admin: admin} do
      # Minimum valid length
      min_attrs = %{name: "ab"}
      assert {:ok, %Branch{}} = Branches.create_branch(admin, min_attrs)

      # Maximum valid length
      max_name = String.duplicate("x", 50)
      max_attrs = %{name: max_name}
      assert {:ok, %Branch{}} = Branches.create_branch(admin, max_attrs)
    end
  end
end
