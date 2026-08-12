defmodule Delivest.Identity.RolesTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.{Role, Roles}
  import Delivest.Factory

  setup do
    admin_role =
      insert(:role,
        permissions: ["roles.read", "roles.create", "roles.update", "roles.delete"]
      )

    admin = insert(:staff, role: admin_role)
    employee = insert(:staff, role: insert(:role, permissions: []))

    %{admin: admin, employee: employee}
  end

  describe "list_roles/2 and list_all_roles/1" do
    test "should return list of roles with flop pagination", %{admin: admin} do
      insert_list(3, :role)

      {:ok, {roles, meta}} = Roles.list_roles(admin, %{page: 1, page_size: 2})

      assert length(roles) == 2
      assert meta.total_count == 5
      assert meta.current_page == 1
    end

    test "should return all roles without pagination", %{admin: admin} do
      insert_list(2, :role)
      roles = Roles.list_all_roles(admin)

      assert length(roles) == 4
    end

    test "should return forbidden if user lacks roles.read", %{employee: employee} do
      assert {:error, :forbidden} = Roles.list_roles(employee, %{})
      assert {:error, :forbidden} = Roles.list_all_roles(employee)
    end
  end

  describe "get_role/2 and get_role_by_name/2" do
    test "should return role by id if role exists and user has rights", %{admin: admin} do
      role = insert(:role)
      assert {:ok, fetched_role} = Roles.get_role(admin, role.id)
      assert fetched_role.id == role.id
    end

    test "should return role by name if role exists and user has rights" do
      role = insert(:role, name: "cashier")
      assert {:ok, fetched_role} = Roles.get_role_by_name("cashier")
      assert fetched_role.id == role.id
    end

    test "should return error if role doesn't exist", %{admin: admin} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Roles.get_role(admin, fake_id)
      assert {:error, :not_found} = Roles.get_role_by_name("non_existent")
    end

    test "should return forbidden if user lacks roles.read", %{employee: employee} do
      role = insert(:role, name: "barista")
      assert {:error, :forbidden} = Roles.get_role(employee, role.id)
    end
  end

  describe "create_role/2 and system_create_role/1" do
    test "should create role with valid data", %{admin: admin} do
      attrs = %{name: "Barista", permissions: ["staff.read"]}

      assert {:ok, %Role{} = role} = Roles.create_role(admin, attrs)
      assert role.name == "Barista"
      assert role.permissions == ["staff.read"]
    end

    test "should create role via system_create_role without user/ACL context" do
      attrs = %{name: "SystemRole", permissions: ["admin"]}

      assert {:ok, %Role{} = role} = Roles.system_create_role(attrs)
      assert role.name == "SystemRole"
    end

    test "should return error when role exists with same name", %{admin: admin} do
      insert(:role, name: "Manager")
      attrs = %{name: "Manager"}

      assert {:error, changeset} = Roles.create_role(admin, attrs)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "should return forbidden if user lacks roles.create", %{employee: employee} do
      attrs = %{name: "CourierRole", permissions: ["admin"]}
      assert {:error, :forbidden} = Roles.create_role(employee, attrs)
    end
  end

  describe "update_role/3" do
    test "should update permissions and attributes", %{admin: admin} do
      role = insert(:role, name: "Shift Supervisor")

      attrs = %{
        name: "Senior Manager",
        permissions: ["staff.read", "staff.update"]
      }

      assert {:ok, updated_role} = Roles.update_role(admin, role, attrs)
      assert updated_role.name == "Senior Manager"
      assert updated_role.permissions == ["staff.read", "staff.update"]
    end

    test "should clear associated staff accounts from cache on role update", %{admin: admin} do
      role = insert(:role)
      staff1 = insert(:staff, role: role)
      staff2 = insert(:staff, role: role)

      other_role = insert(:role)
      other_staff = insert(:staff, role: other_role)

      Cachex.put(:staff_cache, staff1.id, staff1)
      Cachex.put(:staff_cache, staff2.id, staff2)
      Cachex.put(:staff_cache, other_staff.id, other_staff)

      assert {:ok, %Delivest.Identity.Staff{}} = Cachex.get(:staff_cache, staff1.id)
      assert {:ok, %Delivest.Identity.Staff{}} = Cachex.get(:staff_cache, staff2.id)
      assert {:ok, %Delivest.Identity.Staff{}} = Cachex.get(:staff_cache, other_staff.id)

      assert {:ok, _updated_role} = Roles.update_role(admin, role, %{name: "Updated Role"})

      assert {:ok, nil} = Cachex.get(:staff_cache, staff1.id)
      assert {:ok, nil} = Cachex.get(:staff_cache, staff2.id)

      assert {:ok, cached_other} = Cachex.get(:staff_cache, other_staff.id)
      assert cached_other.id == other_staff.id
    end

    test "should return forbidden if user lacks roles.update", %{employee: employee} do
      role = insert(:role)
      attrs = %{name: "Pwned Role"}
      assert {:error, :forbidden} = Roles.update_role(employee, role, attrs)
    end
  end

  describe "delete_role/2" do
    test "should delete role if it isn't linked to any staff", %{admin: admin} do
      role = insert(:role)

      assert {:ok, %Role{}} = Roles.delete_role(admin, role)
      assert {:error, :not_found} = Roles.get_role(admin, role.id)
    end

    test "should not delete role with linked staff account", %{admin: admin} do
      staff = insert(:staff)

      {:ok, role_in_use} = Roles.get_role(admin, staff.role_id)

      assert {:error, :role_in_use} = Roles.delete_role(admin, role_in_use)
      assert {:ok, _} = Roles.get_role(admin, role_in_use.id)
    end

    test "should return forbidden if user lacks roles.delete", %{employee: employee} do
      role = insert(:role)
      assert {:error, :forbidden} = Roles.delete_role(employee, role)
    end
  end
end
