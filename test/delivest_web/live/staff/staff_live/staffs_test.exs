defmodule DelivestWeb.Staff.StaffLive.StaffsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Repo

  test "full staff form saves phone and returns to the filtered list", %{conn: conn} do
    actor = insert(:staff, role: insert(:role, permissions: ["admin"]))
    role = insert(:role, permissions: ["orders.read"])
    target = insert(:staff, role: role, name: "Target employee", login: "target_employee")
    branch = insert(:branch)
    insert(:staff_branch, staff: target, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => actor.id})

    {:ok, view, _} = live(conn, ~p"/staff/employee?search=target")
    assert has_element?(view, "#staff a[href*='/edit']")
    view |> element("#staff a[href*='/edit']") |> render_click()
    {edit_url, _flash} = assert_redirect(view)
    {:ok, view, _} = live(conn, edit_url)
    assert has_element?(view, "#staff-edit-page #account-form")
    view |> form("#account-form", staff: %{phone: "+79991112233"}) |> render_submit()

    assert Repo.reload!(target).phone == "+79991112233"
    {return_url, _flash} = assert_redirect(view)
    assert URI.parse(return_url).fragment == "staff-row-#{target.id}"

    assert return_url
           |> URI.parse()
           |> Map.fetch!(:query)
           |> URI.decode_query()
           |> Map.fetch!("search") == "target"
  end

  test "deleted employee cannot save an already open staff editor", %{conn: conn} do
    actor = insert(:staff, role: insert(:role, permissions: ["admin"]))
    target_role = insert(:role, permissions: ["orders.read"])
    target = insert(:staff, role: target_role, name: "Before", login: "deleted_actor_target")
    conn = init_test_session(conn, %{"staff_id" => actor.id})

    {:ok, view, _} = live(conn, ~p"/staff/employee/#{target.id}/edit")
    Repo.update!(Ecto.Changeset.change(actor, deleted_at: DateTime.utc_now(:second)))
    view |> form("#account-form", staff: %{name: "Deleted actor draft"}) |> render_submit()

    assert has_element?(
             view,
             "#account-form input[name='staff[name]'][value='Deleted actor draft']"
           )

    assert Repo.reload!(target).name == "Before"
  end
end
