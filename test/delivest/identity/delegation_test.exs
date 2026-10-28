defmodule Delivest.Identity.DelegationTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Identity

  setup do
    Cachex.clear(:staff_cache)
    own = insert(:branch)
    other = insert(:branch)

    manager_role =
      insert(:role,
        permissions:
          ~w(staff.read staff.create staff.update staff.delete roles.read roles.update orders.read)
      )

    manager = insert(:staff, role: manager_role)
    insert(:staff_branch, staff: manager, branch: own)
    manager = Repo.preload(manager, [:role, :branches], force: true)

    admin_role = insert(:role, permissions: ["admin"])
    cashier_role = insert(:role, permissions: ["orders.read"])

    %{
      manager: manager,
      own: own,
      other: other,
      admin_role: admin_role,
      cashier_role: cashier_role,
      manager_role: manager_role
    }
  end

  defp staff_in(branch, role) do
    staff = insert(:staff, role: role)
    insert(:staff_branch, staff: staff, branch: branch)
    Repo.preload(staff, [:role, :branches], force: true)
  end

  test "a manager hires only into own branches with weaker roles", ctx do
    attrs = %{
      "login" => "cashier1",
      "password" => "Q1w2e3r4t5!",
      "role_id" => ctx.cashier_role.id
    }

    assert {:ok, _} =
             Identity.create_staff(ctx.manager, Map.put(attrs, "branch_ids", [ctx.own.id]))

    assert {:error, :forbidden} =
             Identity.create_staff(ctx.manager, %{
               attrs
               | "login" => "boss",
                 "role_id" => ctx.admin_role.id
             })

    assert {:error, :forbidden} =
             Identity.create_staff(
               ctx.manager,
               Map.merge(attrs, %{"login" => "far", "branch_ids" => [ctx.other.id]})
             )
  end

  test "a manager cannot raise anyone, including themselves", ctx do
    cashier = staff_in(ctx.own, ctx.cashier_role)

    assert {:error, :forbidden} =
             Identity.update_staff(ctx.manager, cashier, %{"role_id" => ctx.admin_role.id})

    assert {:error, :forbidden} =
             Identity.update_staff(ctx.manager, ctx.manager, %{"branch_ids" => [ctx.other.id]})

    assert {:error, :forbidden} =
             Identity.update_role(ctx.manager, ctx.manager_role, %{"permissions" => ["admin"]})

    assert {:ok, _} = Identity.update_staff(ctx.manager, cashier, %{"name" => "Касса"})
  end

  test "a manager leaves alone staff outside their reach and themselves", ctx do
    foreign = staff_in(ctx.other, ctx.cashier_role)
    admin = staff_in(ctx.own, ctx.admin_role)

    assert {:error, :forbidden} = Identity.update_staff(ctx.manager, foreign, %{"name" => "x"})
    assert {:error, :forbidden} = Identity.soft_delete_staff(ctx.manager, admin)
    assert {:error, :forbidden} = Identity.soft_delete_staff(ctx.manager, ctx.manager)
    refute Identity.manages_role?(ctx.manager, ctx.admin_role)
    assert [_ | _] = roles = Identity.list_assignable_roles(ctx.manager)
    refute ctx.admin_role.id in Enum.map(roles, & &1.id)
  end

  test "an admin keeps full control but cannot delete themselves", ctx do
    admin = staff_in(ctx.own, ctx.admin_role)

    assert {:ok, _} =
             Identity.update_staff(admin, ctx.manager, %{"role_id" => ctx.cashier_role.id})

    assert {:error, :forbidden} = Identity.soft_delete_staff(admin, admin)
  end

  describe "the admin is untouchable" do
    setup ctx do
      director_role = insert(:role, permissions: Delivest.Identity.Definitions.grantable())
      %{admin: staff_in(ctx.own, ctx.admin_role), director: staff_in(ctx.own, director_role)}
    end

    test "nobody makes a second admin", ctx do
      assert {:error, :forbidden} =
               Identity.update_staff(ctx.admin, ctx.manager, %{"role_id" => ctx.admin_role.id})

      assert {:error, :forbidden} =
               Identity.create_role(ctx.admin, %{"name" => "Root", "permissions" => ["admin"]})

      refute ctx.admin_role.id in Enum.map(Identity.list_assignable_roles(ctx.admin), & &1.id)
    end

    test "the admin role is neither edited nor deleted", ctx do
      for actor <- [ctx.admin, ctx.director] do
        assert {:error, :forbidden} =
                 Identity.update_role(actor, ctx.admin_role, %{"permissions" => ["orders.read"]})

        assert {:error, :forbidden} = Identity.delete_role(actor, ctx.admin_role)
      end
    end

    test "others cannot edit, delete or change the password of the admin", ctx do
      assert {:error, :forbidden} =
               Identity.update_staff(ctx.director, ctx.admin, %{"name" => "x"})

      assert {:error, :forbidden} = Identity.soft_delete_staff(ctx.director, ctx.admin)

      assert {:error, :forbidden} =
               Identity.change_password(ctx.director, ctx.admin, %{password: "NewStrongPass1!"})
    end

    test "the admin changes own password and name but keeps the role", ctx do
      assert {:ok, _} =
               Identity.change_password(ctx.admin, ctx.admin, %{password: "NewStrongPass1!"})

      assert {:ok, %{name: "Owner"}} =
               Identity.update_staff(ctx.admin, ctx.admin, %{
                 "name" => "Owner",
                 "role_id" => ctx.admin_role.id
               })

      assert {:error, :forbidden} =
               Identity.update_staff(ctx.admin, ctx.admin, %{"role_id" => ctx.cashier_role.id})
    end

    test "a deleted staff member cannot sign in", ctx do
      staff = staff_in(ctx.own, ctx.cashier_role)
      {:ok, _} = Identity.change_password(ctx.admin, staff, %{password: "NewStrongPass1!"})
      {:ok, _} = Identity.soft_delete_staff(ctx.admin, staff)

      assert {:error, :invalid_credentials} =
               Identity.authenticate(staff.login, "NewStrongPass1!")

      assert {:error, :not_found} = Identity.get_staff(staff.id)
    end
  end
end
