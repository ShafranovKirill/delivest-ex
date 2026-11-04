defmodule DelivestWeb.Staff.RoleLive.RolesTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "an administrator can create missing base roles without replacing custom roles", %{
    conn: conn
  } do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    cashier = insert(:role, name: "Кассир", permissions: ["orders.read"])

    {:ok, view, _html} =
      live(init_test_session(conn, %{"staff_id" => staff.id}), ~p"/staff/roles")

    assert view |> element("#seed-roles") |> render_click() =~ "Base roles created"
    assert render(view) =~ "Управляющий франшизой"
    assert Delivest.Repo.get!(Delivest.Identity.Role, cashier.id).permissions == ["orders.read"]
    assert view |> element("#seed-roles") |> render_click() =~ "All base roles already exist"
  end

  test "a non-administrator cannot seed roles by sending the event", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["roles.read", "roles.create"]))

    {:ok, view, _html} =
      live(init_test_session(conn, %{"staff_id" => staff.id}), ~p"/staff/roles")

    refute has_element?(view, "#seed-roles")
    assert render_click(view, "seed_roles") =~ "Only administrators can create base roles"
    refute render(view) =~ "Управляющий франшизой"
  end

  describe "roles management page" do
    test "renders the roles page and available role cards", %{conn: conn} do
      admin_role = insert(:role, name: "Super Admin", permissions: ["admin"])
      staff = insert(:staff, role: admin_role)
      manager_role = insert(:role, name: "Manager", permissions: ["roles.read"])

      conn = init_test_session(conn, %{"staff_id" => staff.id})

      {:ok, _lv, html} = live(conn, ~p"/staff/roles")

      assert html =~ "Roles Management"
      assert html =~ "Create Role"
      assert html =~ "Super Admin"
      assert html =~ manager_role.name
    end
  end
end
