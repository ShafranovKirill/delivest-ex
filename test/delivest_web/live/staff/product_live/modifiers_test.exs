defmodule DelivestWeb.Staff.ProductLive.ModifiersTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Net.{Modifier, ModifierGroup, Modifiers}
  alias Delivest.Repo

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "a manager builds a group, adds a modifier with an article and stops it", %{conn: conn} do
    branch = insert(:branch, is_active: true)

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, [
          "products.read",
          "products.update",
          "catalog.global.manage",
          "stops.update"
        ]),
        ~p"/staff/b/#{branch}/products/modifiers"
      )

    lv |> element("button[phx-click=new_group]") |> render_click()

    lv
    |> form("#group-form", group: %{name: "Добавки", required: "true", max: "3"})
    |> render_submit()

    group = Repo.get_by!(ModifierGroup, name: "Добавки")
    assert {group.min, group.max} == {1, 3}

    lv |> element("#group-#{group.id} button[phx-click=new_modifier]") |> render_click()

    lv |> form("#modifier-form", modifier: %{name: "Сыр", price: "50"}) |> render_submit()

    cheese = Repo.get_by!(Modifier, name: "Сыр")
    assert {cheese.price, cheese.max_quantity} == {5_000, 1}

    lv |> element("#modifier-article-#{cheese.id}") |> render_click()
    lv |> form("#article-form", article: %{value: "77"}) |> render_submit()
    assert Modifiers.crm_ids([cheese.id], "frontpad", branch.id) == %{cheese.id => "77"}

    lv |> element("#modifier-#{cheese.id} button[phx-click=stop]") |> render_click()
    assert MapSet.member?(Modifiers.stopped_ids(branch.id), cheese.id)
  end

  test "global catalog editor saves definition without branch article permission", %{conn: conn} do
    branch = insert(:branch)
    group = Repo.insert!(%ModifierGroup{name: "Size", min: 0, max: 1})
    modifier = Repo.insert!(%Modifier{group_id: group.id, name: "Small", price: 100})
    article_staff = insert(:staff, role: insert(:role, permissions: ["products.update"]))
    insert(:staff_branch, staff: article_staff, branch: branch)
    assert {:ok, _} = Modifiers.put_crm_id(article_staff, modifier, branch.id, :frontpad, "77")

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["products.read", "catalog.global.manage"]),
        ~p"/staff/b/#{branch}/products/modifiers"
      )

    assert has_element?(lv, "#modifier-edit-#{modifier.id}")
    refute has_element?(lv, "#modifier-article-#{modifier.id}")

    lv |> element("#modifier-edit-#{modifier.id}") |> render_click()
    lv |> form("#modifier-form", modifier: %{name: "Medium", price: "2"}) |> render_submit()

    assert Repo.get!(Modifier, modifier.id).name == "Medium"
    assert Modifiers.crm_ids([modifier.id], "frontpad", branch.id) == %{modifier.id => "77"}
  end

  test "branch editor changes only own article and cannot edit global definition", %{conn: conn} do
    branch = insert(:branch)
    other = insert(:branch)
    group = Repo.insert!(%ModifierGroup{name: "Size", min: 0, max: 1})
    modifier = Repo.insert!(%Modifier{group_id: group.id, name: "Small", price: 100})

    {:ok, lv, _html} =
      live(
        sign_in(conn, branch, ["products.read", "products.update"]),
        ~p"/staff/b/#{branch}/products/modifiers"
      )

    refute has_element?(lv, "#modifier-edit-#{modifier.id}")
    assert has_element?(lv, "#modifier-article-#{modifier.id}")

    lv |> element("#modifier-article-#{modifier.id}") |> render_click()
    lv |> form("#article-form", article: %{value: "77"}) |> render_submit()

    assert Repo.get!(Modifier, modifier.id).name == "Small"
    assert Modifiers.crm_ids([modifier.id], "frontpad", branch.id) == %{modifier.id => "77"}
    assert Modifiers.crm_ids([modifier.id], "frontpad", other.id) == %{}
  end
end
