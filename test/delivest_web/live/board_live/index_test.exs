defmodule DelivestWeb.BoardLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{OrderTransition, Orders}
  alias Delivest.Repo

  defp board_branch do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, board_token: "board-#{branch.id}"})
    branch
  end

  defp order(branch, changes) do
    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  test "numbers move from cooking to ready with a chime", %{conn: conn} do
    branch = board_branch()
    order = order(branch, status: :preparing)

    {:ok, lv, _html} = live(conn, ~p"/board/board-#{branch.id}")

    assert has_element?(
             lv,
             "#board-preparing #board-order-#{order.id}",
             to_string(order.daily_number)
           )

    refute has_element?(lv, "#board-ready #board-order-#{order.id}")

    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    {:ok, _order} = Orders.advance_order(order, :ready, {:staff, admin})

    order_id = order.id
    assert_push_event(lv, "board:ready", %{newest: ^order_id, hold_ms: 15_000})
    assert has_element?(lv, ~s(#board-ready #board-order-#{order.id}[data-fresh]))
    refute has_element?(lv, "#board-preparing #board-order-#{order.id}")

    {:ok, _order} = Orders.advance_order(Repo.reload!(order), :completed, {:staff, admin})
    refute has_element?(lv, "#board-order-#{order.id}")
  end

  test "several ready orders arrive together and the freshest is the priority", %{conn: conn} do
    branch = board_branch()
    first = order(branch, status: :accepted)
    second = order(branch, status: :accepted)

    {:ok, lv, _html} = live(conn, ~p"/board/board-#{branch.id}")

    now = DateTime.utc_now()

    for {order, seconds_ago} <- [{first, 2}, {second, 1}] do
      order |> Ecto.Changeset.change(status: :ready) |> Repo.update!()

      Repo.insert!(%OrderTransition{
        order_id: order.id,
        from: :preparing,
        to: :ready,
        source: :staff,
        inserted_at: DateTime.add(now, -seconds_ago, :second)
      })
    end

    send(lv.pid, :tick)

    assert_push_event(lv, "board:ready", %{ids: ids, newest: newest, hold_ms: 15_000})
    assert newest == second.id
    assert Enum.sort(ids) == Enum.sort([first.id, second.id])

    assert has_element?(lv, ~s(#board-ready #board-order-#{first.id}[data-fresh]))
    assert has_element?(lv, ~s(#board-ready #board-order-#{second.id}[data-fresh]))
  end

  test "the board speaks the screen language", %{conn: conn} do
    branch = board_branch()
    conn = init_test_session(conn, %{"locale" => "ru"})

    {:ok, lv, _html} = live(conn, ~p"/board/board-#{branch.id}")

    assert render(lv) =~ "Готовятся"
  end

  test "an unknown link is not found", %{conn: conn} do
    assert_raise DelivestWeb.BoardLive.NotFound, fn -> live(conn, ~p"/board/unknown") end
  end
end
