defmodule Delivest.Identity.AclTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.{Acl, Staff}
  alias Delivest.Repo
  import Delivest.Factory
  import Ecto.Query

  describe "can?/2" do
    test "should return false when staff is nil" do
      refute Acl.can?(nil, "staff.read")
    end

    test "should return true when staff has 'admin' permission" do
      role = build(:role, permissions: ["admin"])
      staff = build(:staff, role: role)

      assert Acl.can?(staff, "staff.read")
      assert Acl.can?(staff, "any.other.permission")
    end

    test "should return true when staff has exact permission" do
      role = build(:role, permissions: ["staff.read", "staff.create"])
      staff = build(:staff, role: role)

      assert Acl.can?(staff, "staff.read")
      assert Acl.can?(staff, "staff.create")
    end

    test "should return false when staff lacks permission and is not admin" do
      role = build(:role, permissions: ["staff.read"])
      staff = build(:staff, role: role)

      refute Acl.can?(staff, "staff.delete")
      refute Acl.can?(staff, "staff.update")
    end
  end

  describe "can_any?/2" do
    test "should return false when staff is nil" do
      refute Acl.can_any?(nil, ["staff.read", "staff.write"])
    end

    test "should return true when staff has 'admin' permission" do
      role = build(:role, permissions: ["admin"])
      staff = build(:staff, role: role)

      assert Acl.can_any?(staff, ["staff.delete", "unknown.perm"])
    end

    test "should return true if staff has at least one matching permission" do
      role = build(:role, permissions: ["staff.read"])
      staff = build(:staff, role: role)

      assert Acl.can_any?(staff, ["staff.delete", "staff.read"])
    end

    test "should return false when staff has none of the requested permissions" do
      role = build(:role, permissions: ["staff.read"])
      staff = build(:staff, role: role)

      refute Acl.can_any?(staff, ["staff.delete", "staff.update"])
    end
  end

  describe "scope_by_branch/3" do
    test "should return empty result set (WHERE false) when staff is nil" do
      insert(:staff)
      query = from(s in Staff, select: s)

      scoped_query = Acl.scope_by_branch(query, nil, "staff.read")
      assert Repo.all(scoped_query) == []
    end

    test "should return original query when staff is admin" do
      staff_record = insert(:staff)

      role = build(:role, permissions: ["admin"])
      staff_actor = build(:staff, role: role)

      query = from(s in Staff, select: s)
      scoped_query = Acl.scope_by_branch(query, staff_actor, "staff.read")

      results = Repo.all(scoped_query)
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == staff_record.id))
    end

    test "should return empty result set (WHERE false) when staff lacks permission" do
      insert(:staff)

      role = build(:role, permissions: ["staff.read"])
      staff_actor = build(:staff, role: role)

      query = from(s in Staff, select: s)
      scoped_query = Acl.scope_by_branch(query, staff_actor, "staff.delete")

      assert Repo.all(scoped_query) == []
    end
  end

  describe "can?/2 - advanced scenarios" do
    test "should handle empty permissions list" do
      role = build(:role, permissions: [])
      staff = build(:staff, role: role)

      refute Acl.can?(staff, "any.permission")
    end

    test "should be case-sensitive for permissions" do
      role = build(:role, permissions: ["staff.Read"])
      staff = build(:staff, role: role)

      refute Acl.can?(staff, "staff.read")
      assert Acl.can?(staff, "staff.Read")
    end

    test "should not match partial permission strings" do
      role = build(:role, permissions: ["staff.read.basic"])
      staff = build(:staff, role: role)

      refute Acl.can?(staff, "staff.read")
      assert Acl.can?(staff, "staff.read.basic")
    end
  end

  describe "can_any?/2 - advanced scenarios" do
    test "should return false with empty permission list" do
      role = build(:role, permissions: ["staff.read"])
      staff = build(:staff, role: role)

      refute Acl.can_any?(staff, [])
    end

    test "should work with single permission check" do
      role = build(:role, permissions: ["staff.create"])
      staff = build(:staff, role: role)

      assert Acl.can_any?(staff, ["staff.create"])
      refute Acl.can_any?(staff, ["staff.delete"])
    end
  end

  describe "has_branch_access?/2" do
    test "should return false when staff is nil" do
      branch = insert(:branch)
      refute Acl.has_branch_access?(nil, branch.id)
    end

    test "should return true when staff has 'admin' permission" do
      role = build(:role, permissions: ["admin"])
      staff = build(:staff, role: role)
      branch = insert(:branch)

      assert Acl.has_branch_access?(staff, branch.id)
    end

    test "should return true when staff has branch assignment" do
      branch = insert(:branch)
      role = build(:role, permissions: ["staff.read"])
      staff = insert(:staff, role: role)
      insert(:staff_branch, staff: staff, branch: branch)

      staff = Repo.preload(staff, :branches)

      assert Acl.has_branch_access?(staff, branch.id)
    end

    test "should return false when staff lacks branch access and is not admin" do
      role = build(:role, permissions: ["staff.read"])
      staff = build(:staff, role: role)
      branch = insert(:branch)

      staff = Repo.preload(staff, :branches)

      refute Acl.has_branch_access?(staff, branch.id)
    end

    test "should return false when branches association is not preloaded" do
      role = build(:role, permissions: ["staff.read"])
      staff = insert(:staff, role: role)
      branch = insert(:branch)

      refute Acl.has_branch_access?(staff, branch.id)
    end

    test "should handle multiple branch assignments" do
      role = build(:role, permissions: ["staff.read"])
      staff = insert(:staff, role: role)
      branch1 = insert(:branch)
      branch2 = insert(:branch)
      branch3 = insert(:branch)

      insert(:staff_branch, staff: staff, branch: branch1)
      insert(:staff_branch, staff: staff, branch: branch2)

      staff = Repo.preload(staff, :branches)

      assert Acl.has_branch_access?(staff, branch1.id)
      assert Acl.has_branch_access?(staff, branch2.id)
      refute Acl.has_branch_access?(staff, branch3.id)
    end
  end
end
