defmodule Delivest.Identity.AclTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.{Acl, Staff}
  alias Delivest.Repo
  import Delivest.Factory

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

  describe "scope_query/3" do
    test "should return empty result set (WHERE false) when staff is nil" do
      insert(:staff)
      query = Staff

      scoped_query = Acl.scope_query(query, nil, "staff.read")
      assert Repo.all(scoped_query) == []
    end

    test "should return original query when staff has permission" do
      staff_record = insert(:staff)

      role = build(:role, permissions: ["staff.read"])
      staff_actor = build(:staff, role: role)

      query = Staff
      scoped_query = Acl.scope_query(query, staff_actor, "staff.read")

      results = Repo.all(scoped_query)
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == staff_record.id))
    end

    test "should return original query when staff is admin" do
      staff_record = insert(:staff)

      role = build(:role, permissions: ["admin"])
      staff_actor = build(:staff, role: role)

      query = Staff
      scoped_query = Acl.scope_query(query, staff_actor, "staff.read")

      results = Repo.all(scoped_query)
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == staff_record.id))
    end

    test "should return empty result set (WHERE false) when staff lacks permission" do
      insert(:staff)

      role = build(:role, permissions: ["staff.read"])
      staff_actor = build(:staff, role: role)

      query = Staff
      scoped_query = Acl.scope_query(query, staff_actor, "staff.delete")

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
end
