defmodule DelivestWeb.Staff.KitchenLive.IndexTest do
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
    cook = insert(:staff, role: build(:role, permissions: ["orders.read", "orders.cook"]))
    insert(:staff_branch, staff: cook, branch: branch)

    %{conn: init_test_session(conn, %{"staff_id" => cook.id}), branch: branch, cook: cook}
  end

  defp cooking(branch, changes \\ []) do
    branch.id
    |> order_fixture(attrs: %{"comment" => "без лука"})
    |> Ecto.Changeset.change([status: :preparing] ++ changes)
    |> Repo.update!()
    |> Repo.preload(:items)
  end

  test "shows cooking orders with items and comment", %{conn: conn, branch: branch} do
    order = cooking(branch)

    {:ok, lv, html} = live(conn, ~p"/staff/b/#{branch}/kitchen")

    assert html =~ "##{order.number}"
    assert html =~ hd(order.items).title
    assert html =~ "без лука"
    assert has_element?(lv, "#ready-#{order.id}")
    assert has_element?(lv, "#kitchen-offline[hidden]")
  end

  test "done shows undo and undo brings the button back", %{conn: conn, branch: branch} do
    order = cooking(branch)
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/kitchen")

    lv |> element("#ready-#{order.id}") |> render_click()
    assert has_element?(lv, "#undo-#{order.id}")
    assert Repo.reload!(order).status == :preparing

    lv |> element("#undo-#{order.id}") |> render_click()
    assert has_element?(lv, "#ready-#{order.id}")
    assert Kitchen.pending_ready(branch.id) == %{}
  end

  test "a new order arrives with a sound", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/kitchen")
    assert has_element?(lv, "#kitchen-empty")

    order = cooking(branch)
    Kitchen.changed(branch.id)

    assert_push_event(lv, "kitchen:new", %{})
    assert has_element?(lv, "#ticket-#{order.id}.animate-pulse")
  end

  test "a late order turns red", %{conn: conn, branch: branch} do
    past = NaiveDateTime.add(NaiveDateTime.local_now(), -3, :hour)
    order = cooking(branch, cook_by: NaiveDateTime.truncate(past, :second))

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/kitchen")

    assert has_element?(lv, "#ticket-#{order.id}.border-error")
  end

  test "says so when the kitchen is off", %{conn: conn} do
    branch = insert(:branch)
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => admin.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/kitchen")

    assert has_element?(lv, "#kitchen-off")
  end

  test "an operator without kitchen rights is sent away", %{conn: conn, branch: branch} do
    operator = insert(:staff, role: build(:role, permissions: ["orders.read", "orders.update"]))
    insert(:staff_branch, staff: operator, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => operator.id})

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{branch}/kitchen")
  end

  test "the kitchen account lands on the screen and stays signed in", %{
    conn: conn,
    branch: branch,
    cook: cook
  } do
    conn =
      post(conn, ~p"/staff/auth/log_in", %{
        "user" => %{"login" => cook.login, "password" => "Q1w2e3r4t5!"}
      })

    assert %{max_age: max_age} = conn.resp_cookies["_delivest_kitchen"]
    assert max_age > 60 * 60 * 24 * 300

    conn =
      build_conn()
      |> put_req_cookie("_delivest_kitchen", conn.resp_cookies["_delivest_kitchen"].value)
      |> get(~p"/staff")

    assert redirected_to(conn) =~ "/staff/branches/select/#{branch.id}"

    conn = conn |> recycle() |> get(~p"/staff/branches/select/#{branch.id}")
    assert redirected_to(conn) == ~p"/staff/b/#{branch}/kitchen"
  end
end
