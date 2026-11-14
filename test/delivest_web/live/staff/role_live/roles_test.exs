defmodule DelivestWeb.Staff.RoleLive.RolesTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory
  alias Delivest.Features

  test "role card opens a full page and returns to its list position", %{conn: conn} do
    actor = insert(:staff, role: insert(:role, permissions: ["admin"]))
    role = insert(:role, name: "Operations", permissions: ["roles.read"])
    conn = init_test_session(conn, %{"staff_id" => actor.id})

    {:ok, list, _} = live(conn, ~p"/staff/roles")
    assert has_element?(list, "#role-card-#{role.id}")
    list |> element("#role-card-#{role.id} a.cursor-pointer") |> render_click()
    {edit_url, _flash} = assert_redirect(list)
    assert URI.parse(edit_url).path == ~p"/staff/roles/#{role.id}/edit"

    {:ok, edit, _} = live(conn, edit_url)
    assert has_element?(edit, "#role-edit-page #role-form")
    edit |> element("#role-back-to-list") |> render_click()
    {return_url, _flash} = assert_redirect(edit)
    assert URI.parse(return_url).fragment == "role-card-#{role.id}"
  end

  test "disabled feature permissions stay hidden and forged additions are ignored", %{conn: conn} do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    role = insert(:role, permissions: ["roles.read", "segments.read", "marketing.read"])
    conn = init_test_session(conn, %{"staff_id" => admin.id})
    {:ok, view, _} = live(conn, ~p"/staff/roles/#{role.id}/edit")
    refute has_element?(view, ~s([id="checkbox-segments.read"]))
    refute has_element?(view, ~s([id="checkbox-segments.manage"]))
    refute has_element?(view, ~s([id="checkbox-marketing.read"]))
    refute has_element?(view, ~s([id="checkbox-marketing.manage"]))

    assert {:ok, updated} =
             Delivest.Identity.update_role(admin, role, %{
               "permissions" => ["roles.read", "segments.manage", "marketing.manage"]
             })

    assert "segments.read" in updated.permissions
    assert "marketing.read" in updated.permissions
    refute "segments.manage" in updated.permissions
    refute "marketing.manage" in updated.permissions

    assert {:ok, renamed} = Delivest.Identity.update_role(admin, updated, %{name: "Renamed role"})
    assert renamed.name == "Renamed role"
    assert "segments.read" in renamed.permissions
    assert "marketing.read" in renamed.permissions

    assert {:ok, created} =
             Delivest.Identity.create_role(
               admin,
               %{
                 name: "No hidden feature grant",
                 permissions: ["roles.read", "segments.manage", "marketing.manage"]
               }
             )

    assert created.permissions == ["roles.read"]
  end

  test "segment permissions remain available while marketing is disabled", %{conn: conn} do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")

    conn = init_test_session(conn, %{"staff_id" => admin.id})
    {:ok, view, _} = live(conn, ~p"/staff/roles/new")
    assert has_element?(view, ~s([id="checkbox-segments.manage"]))
    refute has_element?(view, ~s([id="checkbox-marketing.manage"]))
  end

  test "enabled feature permissions are available to grant", %{conn: conn} do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    assert Features.enabled?("segments", :franchise)
    assert Features.enabled?("marketing_policies", :franchise)

    conn = init_test_session(conn, %{"staff_id" => admin.id})
    {:ok, view, _} = live(conn, ~p"/staff/roles/new")
    assert has_element?(view, ~s([id="checkbox-segments.manage"]))
    assert has_element?(view, ~s([id="checkbox-marketing.manage"]))

    assert {:ok, created} =
             Delivest.Identity.create_role(admin, %{
               name: "Marketing manager",
               permissions: ["segments.manage", "marketing.manage"]
             })

    assert "segments.manage" in created.permissions
    assert "marketing.manage" in created.permissions
  end

  test "an administrator can create missing base roles without replacing custom roles", %{
    conn: conn
  } do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    cashier = insert(:role, name: "Кассир", permissions: ["orders.read"])

    {:ok, view, _html} =
      live(init_test_session(conn, %{"staff_id" => staff.id}), ~p"/staff/roles")

    assert has_element?(view, "#staff-page-header-actions #seed-roles")

    assert render_click(view, "seed_roles") =~ "Base roles created"
    assert render(view) =~ "Управляющий франшизой"
    assert Delivest.Repo.get!(Delivest.Identity.Role, cashier.id).permissions == ["orders.read"]
    assert render_click(view, "seed_roles") =~ "All base roles already exist"
  end

  test "revoked role editor keeps the draft and cannot save", %{conn: conn} do
    actor_role = insert(:role, permissions: ["roles.read", "roles.update"])
    actor = insert(:staff, role: actor_role)
    target = insert(:role, name: "Before", permissions: ["roles.read"])
    conn = init_test_session(conn, %{"staff_id" => actor.id})

    {:ok, view, _} = live(conn, ~p"/staff/roles/#{target.id}/edit")
    assert has_element?(view, "#role-edit-page #role-form")
    Delivest.Repo.update!(Ecto.Changeset.change(actor_role, permissions: ["roles.read"]))
    view |> form("#role-form", role: %{name: "Draft after revoke"}) |> render_submit()

    assert has_element?(view, "#role-form input[name='role[name]'][value='Draft after revoke']")
    assert Delivest.Repo.reload!(target).name == "Before"
    assert has_element?(view, "#role-save-error")
  end

  test "deleted employee cannot save an already open role editor", %{conn: conn} do
    actor = insert(:staff, role: insert(:role, permissions: ["admin"]))
    target = insert(:role, name: "Before", permissions: ["roles.read"])
    conn = init_test_session(conn, %{"staff_id" => actor.id})

    {:ok, view, _} = live(conn, ~p"/staff/roles/#{target.id}/edit")
    Delivest.Repo.update!(Ecto.Changeset.change(actor, deleted_at: DateTime.utc_now(:second)))
    view |> form("#role-form", role: %{name: "Deleted actor draft"}) |> render_submit()

    assert has_element?(view, "#role-form input[name='role[name]'][value='Deleted actor draft']")
    assert has_element?(view, "#role-save-error")
    assert Delivest.Repo.reload!(target).name == "Before"
  end

  test "a non-administrator cannot seed roles by sending the event", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["roles.read", "roles.create"]))

    {:ok, view, _html} =
      live(init_test_session(conn, %{"staff_id" => staff.id}), ~p"/staff/roles")

    refute has_element?(view, "#staff-page-header-actions #seed-roles")

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
