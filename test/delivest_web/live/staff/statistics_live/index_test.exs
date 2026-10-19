defmodule DelivestWeb.Staff.StatisticsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  defp login(conn, permissions) do
    branch = insert(:branch, name: "Main")
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)

    {init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}), branch}
  end

  test "shows sales, products and categories of the branch", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    category = insert(:category, name: "Горячее")

    product =
      insert_branch_product(branch.id, name: "Хинкали", price: 300, category_id: category.id)

    order_fixture(branch.id, product: product, quantity: 2)

    {:ok, lv, html} = live(conn, ~p"/staff/statistics?period=today")
    assert html =~ "Statistics"
    assert html =~ "600 ₽"

    html = lv |> element("a", "Products") |> render_click()
    assert html =~ "Хинкали"

    html = lv |> element("a", "Categories") |> render_click()
    assert html =~ "Горячее"
  end

  test "custom period comes from the filter form", %{conn: conn} do
    {conn, _branch} = login(conn, ["statistics.read"])
    {:ok, lv, _html} = live(conn, ~p"/staff/statistics")

    lv
    |> form("#statistics-filter", %{"period" => "custom"})
    |> render_change()

    today = Delivest.LocalTime.today()
    from = Date.to_iso8601(Date.add(today, -6))
    to = Date.to_iso8601(today)

    query = %{
      "from" => from,
      "period" => "custom",
      "sort" => "revenue",
      "tab" => "sales",
      "to" => to
    }

    assert_patch(lv, ~p"/staff/statistics?#{query}")
    assert has_element?(lv, ~s{input[name="from"][value="#{from}"]})
  end

  test "requires the statistics.read permission", %{conn: conn} do
    {conn, _branch} = login(conn, ["orders.read"])

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} = live(conn, ~p"/staff/statistics")
  end
end
