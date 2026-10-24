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

    assert {:ok, _} = Identity.update_staff(admin, ctx.manager, %{"role_id" => ctx.admin_role.id})
    assert {:error, :forbidden} = Identity.soft_delete_staff(admin, admin)
  end
end
