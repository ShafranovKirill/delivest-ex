defmodule DelivestWeb.Staff.OrderLive.OrdersTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  describe "orders management page" do
    test "renders the orders page with filtering controls for the active branch", %{conn: conn} do
      branch = insert(:branch, name: "Delivery Branch")
      admin_role = insert(:role, permissions: ["admin"])
      staff = insert(:staff, role: admin_role)

      conn =
        init_test_session(conn, %{
          "staff_id" => staff.id,
          "active_branch_id" => branch.id
        })

      {:ok, _lv, html} = live(conn, ~p"/staff/orders")

      assert html =~ "Orders"
      assert html =~ "All Statuses"
      assert html =~ "Status:"
    end
  end

  describe "order actions" do
    setup %{conn: conn} do
      branch = insert(:branch, name: "Main")
      order = create_order(branch.id)

      %{conn: conn, branch: branch, order: order}
    end

    defp create_order(branch_id) do
      product = insert_branch_product(branch_id, price: 150)

      {:ok, cart} =
        Delivest.Oms.Carts.create_cart(%{
          session_id: "lv-#{System.unique_integer([:positive])}",
          branch_id: branch_id
        })

      {:ok, _, _} = Delivest.Oms.Carts.add_item(cart.id, product.id, 1)

      {:ok, order} =
        Delivest.Oms.Orders.create_order(%{
          "cart_id" => cart.id,
          "branch_id" => branch_id,
          "fulfillment_type" => "pickup",
          "payment_method" => "cash"
        })

      order
    end

    defp login(conn, permissions, branch) do
      staff = insert(:staff, role: insert(:role, permissions: permissions))
      insert(:staff_branch, staff: staff, branch: branch)

      init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    end

    test "status can be changed from the list", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/orders")

      lv
      |> element(~s{form[phx-value-order-id="#{order.id}"]:has(select[name="status"])})
      |> render_change(%{"status" => "preparing"})

      assert Delivest.Repo.reload!(order).status == :preparing
    end

    test "a new order is confirmed with one click", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/orders")

      lv |> element("#order-confirm-#{order.id}") |> render_click()

      assert Delivest.Repo.reload!(order).status == :preparing
      refute has_element?(lv, "#order-confirm-#{order.id}")
    end

    test "an unmapped Frontpad status code is shown", %{conn: conn, branch: branch, order: order} do
      order = order |> Ecto.Changeset.change(status: :crm) |> Delivest.Repo.update!()

      {:ok, _order} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "sent",
          remote_status_code: "4"
        })

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/orders")

      assert has_element?(lv, "#order-unmapped-#{order.id}", "4")
    end

    test "read-only staff cannot change orders", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["orders.read"], branch), ~p"/staff/orders")

      html =
        lv
        |> element(~s{form[phx-value-order-id="#{order.id}"]:has(select[name="status"])})
        |> render_change(%{"status" => "cancelled"})

      assert html =~ "Permission denied"
      assert Delivest.Repo.reload!(order).status == :created
    end

    test "orders of other branches do not appear live", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/orders")

      other_branch = insert(:branch)
      foreign_order = create_order(other_branch.id)

      refute has_element?(lv, "#orders-#{foreign_order.id}")

      own_order = create_order(branch.id)
      assert has_element?(lv, "#orders-#{own_order.id}")
    end

    test "orders are split into pages", %{conn: conn, branch: branch, order: first} do
      first
      |> Ecto.Changeset.change(inserted_at: DateTime.add(first.inserted_at, -60))
      |> Delivest.Repo.update!()

      second = create_order(branch.id)
      conn = login(conn, ["admin"], branch)

      {:ok, lv, _html} = live(conn, ~p"/staff/orders?page_size=1")
      assert has_element?(lv, "#orders-#{second.id}")
      refute has_element?(lv, "#orders-#{first.id}")

      {:ok, lv, _html} = live(conn, ~p"/staff/orders?page_size=1&page=2")
      assert has_element?(lv, "#orders-#{first.id}")
      refute has_element?(lv, "#orders-#{second.id}")
    end

    test "orders of another branch cannot be edited", %{conn: conn, branch: branch} do
      other_order = create_order(insert(:branch).id)

      assert {:error, {:redirect, %{to: "/staff/orders"}}} =
               live(login(conn, ["admin"], branch), ~p"/staff/orders/#{other_order.id}/edit")
    end
  end
end
