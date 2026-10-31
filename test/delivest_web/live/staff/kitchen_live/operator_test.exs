defmodule DelivestWeb.Staff.KitchenLive.OperatorTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Kitchen
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, kitchen: %{enabled: true}})
    operator = staff(["orders.read", "orders.update"], branch)

    %{conn: init_test_session(conn, %{"staff_id" => operator.id}), branch: branch}
  end

  defp staff(permissions, branch) do
    staff = insert(:staff, role: build(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp orders_page(conn, branch), do: live(conn, ~p"/staff/b/#{branch}/orders")

  test "the header shows whether the kitchen screen is open", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = orders_page(conn, branch)
    assert lv |> element("#kitchen-indicator") |> render() =~ "Kitchen"

    cook = staff(["orders.read", "orders.cook"], branch)
    kitchen_conn = init_test_session(build_conn(), %{"staff_id" => cook.id})
    {:ok, _kitchen, _html} = live(kitchen_conn, ~p"/staff/b/#{branch}/kitchen")

    assert eventually(fn ->
             lv |> element("#kitchen-indicator") |> render() =~ "Kitchen online"
           end)
  end

  test "a ready order from the kitchen rings and flashes", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = orders_page(conn, branch)
    order = order_fixture(branch.id)

    Phoenix.PubSub.broadcast(
      Delivest.PubSub,
      "kitchen:#{branch.id}",
      {:kitchen_order_ready, order}
    )

    assert_push_event(lv, "kitchen:ready", %{})
    assert render(lv) =~ "Order ##{order.daily_number} is ready"
  end

  test "an order past cook_by still cooking raises the alarm", %{conn: conn, branch: branch} do
    past = DateTime.add(DateTime.utc_now(), -3, :hour)

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(status: :preparing, cook_by: DateTime.truncate(past, :second))
      |> Repo.update!()

    {:ok, lv, _html} = orders_page(conn, branch)

    assert has_element?(lv, "#kitchen-late-#{order.id}")
  end

  test "the next step of a confirmed order sends it to the kitchen", %{
    conn: conn,
    branch: branch
  } do
    later = DateTime.add(DateTime.utc_now(), 5, :hour)

    order =
      order_fixture(branch.id,
        attrs: %{
          "cook_by" => DateTime.truncate(later, :second) |> DateTime.to_iso8601()
        }
      )

    {:ok, lv, _html} = orders_page(conn, branch)
    lv |> element("#order-next-#{order.id}") |> render_click()
    assert Repo.reload!(order).status == :accepted

    assert lv |> element("#order-next-#{order.id}") |> render() =~ "Send to the kitchen"
    lv |> element("#order-next-#{order.id}") |> render_click()

    assert Repo.reload!(order).status == :preparing
    assert has_element?(lv, "#order-kitchen-clock-#{order.id}")
  end

  test "no kitchen controls without a working kitchen", %{conn: conn} do
    branch = insert(:branch)
    operator = staff(["orders.read", "orders.update"], branch)
    conn = init_test_session(conn, %{"staff_id" => operator.id})

    {:ok, lv, _html} = orders_page(conn, branch)

    refute has_element?(lv, "#kitchen-indicator")
    refute Kitchen.working?(branch.id)
  end

  defp eventually(fun, attempts \\ 20) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(25)
        eventually(fun, attempts - 1)
    end
  end
end
