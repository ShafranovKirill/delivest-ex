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
        sign_in(conn, branch, ["products.read", "products.update", "stops.update"]),
        ~p"/staff/b/#{branch}/products/modifiers"
      )

    lv
    |> form("#new-group", group: %{name: "Добавки", min: "0", max: "3"})
    |> render_submit()

    group = Repo.get_by!(ModifierGroup, name: "Добавки")
    assert group.max == 3

    lv
    |> form("#new-modifier-#{group.id}", modifier: %{name: "Сыр", price: "50", max_quantity: "2"})
    |> render_submit()

    cheese = Repo.get_by!(Modifier, name: "Сыр")
    assert cheese.price == 5_000

    lv
    |> form("#modifier-#{cheese.id}", modifier: %{article: "77"})
    |> render_submit()

    assert Modifiers.crm_ids([cheese.id], "frontpad") == %{cheese.id => "77"}

    lv |> element("#modifier-#{cheese.id} button[phx-click=stop]") |> render_click()
    assert MapSet.member?(Modifiers.stopped_ids(branch.id), cheese.id)
  end
end
