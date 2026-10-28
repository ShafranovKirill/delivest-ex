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

      {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/orders")

      assert html =~ "Orders"
      assert html =~ "By urgency"
      assert html =~ "order-status-tab-created"
      assert html =~ "orders-search"
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
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      lv
      |> element(~s{form[phx-value-order-id="#{order.id}"]:has(select[name="status"])})
      |> render_change(%{"status" => "preparing"})

      assert Delivest.Repo.reload!(order).status == :preparing
    end

    test "the next step button walks the order to completion", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      for status <- [:accepted, :preparing, :ready, :completed] do
        lv |> element("#order-next-#{order.id}") |> render_click()
        assert Delivest.Repo.reload!(order).status == status
      end

      refute has_element?(lv, "#order-next-#{order.id}")
    end

    test "tabs count orders and filter by status", %{conn: conn, branch: branch, order: order} do
      create_order(branch.id)
      |> Ecto.Changeset.change(status: :preparing)
      |> Delivest.Repo.update!()

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#order-status-tab-created", "1")
      assert has_element?(lv, "#order-status-tab-preparing", "1")

      lv |> element("#order-status-tab-preparing") |> render_click()

      refute has_element?(lv, "#orders-#{order.id}")
      assert_patch(lv, ~p"/staff/b/#{branch}/orders?status=preparing")
    end

    test "cancelling asks for a reason", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      lv
      |> element(~s{form[phx-value-order-id="#{order.id}"]:has(select[name="status"])})
      |> render_change(%{"status" => "cancelled"})

      assert Delivest.Repo.reload!(order).status == :created
      assert has_element?(lv, "#cancel-order-form")

      lv
      |> form("#cancel-order-form", cancel: %{reason: "unreachable", note: "Не берёт трубку"})
      |> render_submit()

      assert %{status: :cancelled, cancel_reason: :unreachable} = Delivest.Repo.reload!(order)
      assert has_element?(lv, "#order-cancel-reason-#{order.id}", "Не берёт трубку")
    end

    test "an unmapped Frontpad status code is shown", %{conn: conn, branch: branch, order: order} do
      order = order |> Ecto.Changeset.change(status: :crm) |> Delivest.Repo.update!()

      {:ok, _order} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "sent",
          remote_status_code: "4"
        })

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#order-unmapped-#{order.id}", "4")
    end

    test "read-only staff cannot change orders", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["orders.read"], branch), ~p"/staff/b/#{branch}/orders")

      html =
        lv
        |> element(~s{form[phx-value-order-id="#{order.id}"]:has(select[name="status"])})
        |> render_change(%{"status" => "cancelled"})

      assert html =~ "Permission denied"
      assert Delivest.Repo.reload!(order).status == :created
    end

    test "orders of other branches do not appear live", %{conn: conn, branch: branch} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

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

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders?page_size=1")
      assert has_element?(lv, "#orders-#{first.id}")
      refute has_element?(lv, "#orders-#{second.id}")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders?page_size=1&page=2")
      assert has_element?(lv, "#orders-#{second.id}")
      refute has_element?(lv, "#orders-#{first.id}")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders?page_size=1&sort=time")
      assert has_element?(lv, "#orders-#{second.id}")
    end

    test "orders of another branch cannot be edited", %{conn: conn, branch: branch} do
      other_order = create_order(insert(:branch).id)

      orders = ~p"/staff/b/#{branch}/orders"

      assert {:error, {:redirect, %{to: ^orders}}} =
               live(
                 login(conn, ["admin"], branch),
                 ~p"/staff/b/#{branch}/orders/#{other_order.id}/edit"
               )
    end
  end
end
