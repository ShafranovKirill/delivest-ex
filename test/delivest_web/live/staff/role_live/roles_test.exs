defmodule DelivestWeb.Staff.RoleLive.RolesTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "disabled segment permissions stay hidden and forged additions are ignored", %{conn: conn} do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    role = insert(:role, permissions: ["roles.read", "segments.read"])
    conn = init_test_session(conn, %{"staff_id" => admin.id})
    {:ok, view, _} = live(conn, ~p"/staff/roles/#{role.id}/edit")
    refute has_element?(view, "#checkbox-segments.read")
    refute has_element?(view, "#checkbox-segments.manage")

    assert {:ok, updated} =
             Delivest.Identity.update_role(admin, role, %{
               "permissions" => ["roles.read", "segments.manage"]
             })

    assert "segments.read" in updated.permissions
    refute "segments.manage" in updated.permissions

    assert {:ok, renamed} = Delivest.Identity.update_role(admin, updated, %{name: "Renamed role"})
    assert renamed.name == "Renamed role"
    assert "segments.read" in renamed.permissions

    assert {:ok, created} =
             Delivest.Identity.create_role(
               admin,
               %{name: "No hidden segment grant", permissions: ["roles.read", "segments.manage"]}
             )

    assert created.permissions == ["roles.read"]
  end

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
