defmodule DelivestWeb.Staff.OrderLive.OrdersTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  defp eventually(fun, attempts \\ 120) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        receive do
        after
          25 -> eventually(fun, attempts - 1)
        end
    end
  end

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
      assert html =~ "order-status-select"
      assert html =~ "orders-fullscreen"
      refute html =~ "Manage customer orders, track statuses and process fulfillment."
      refute html =~ "intake-dialog"
      refute html =~ "intake-popover"
      assert html =~ "orders-search"
      assert html =~ "orders-sound-toggle"
    end
  end

  describe "order actions" do
    setup %{conn: conn} do
      branch = insert(:branch)
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

    test "receiving, payment and source filters are URL backed", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, lv, _html} =
        live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders?period=all")

      assert has_element?(lv, "#orders-#{order.id}")

      lv
      |> form("#orders-filter-form", %{"period" => "all", "receiving" => "delivery"})
      |> render_change()

      assert_patch(lv)
      refute has_element?(lv, "#orders-#{order.id}")

      {:ok, filtered, _html} =
        live(
          login(conn, ["admin"], branch),
          ~p"/staff/b/#{branch}/orders?period=all&receiving=pickup&payment=cash&source=app"
        )

      assert has_element?(filtered, "#orders-#{order.id}")
      assert has_element?(filtered, "#orders-receiving option[value='pickup'][selected]")
      assert has_element?(filtered, "#orders-payment option[value='cash'][selected]")
      assert has_element?(filtered, "#orders-source option[value='app'][selected]")
    end

    test "staff cannot jump over a step", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      refute has_element?(lv, ~s{select[name="status"]})

      html = render_click(lv, "advance", %{"order-id" => order.id, "to" => "ready"})

      assert html =~ "The order status has already changed"
      assert Delivest.Repo.reload!(order).status == :created
    end

    test "revoked order permission blocks action in an open queue", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      role = insert(:role, permissions: ["orders.read", "orders.update"])
      staff = insert(:staff, role: role)
      insert(:staff_branch, staff: staff, branch: branch)
      conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders")
      role |> Ecto.Changeset.change(permissions: ["orders.read"]) |> Delivest.Repo.update!()

      render_click(lv, "advance", %{"order-id" => order.id, "to" => "accepted"})
      assert Delivest.Repo.reload!(order).status == :created
    end

    test "the cook moves only kitchen steps", %{conn: conn, branch: branch, order: order} do
      conn = login(conn, ["orders.read", "orders.cook"], branch)
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

      refute has_element?(lv, "#order-next-#{order.id}")
      refute has_element?(lv, "#order-cancel-#{order.id}")

      {:ok, _} = Delivest.Oms.Orders.advance_order(order, :accepted, :system)

      lv |> element("#order-next-#{order.id}") |> render_click()
      lv |> element("#order-next-#{order.id}") |> render_click()
      assert Delivest.Repo.reload!(order).status == :ready
      refute has_element?(lv, "#order-next-#{order.id}")

      assert [_, %{source: :staff, staff_id: staff_id}, %{to: :ready}] =
               Delivest.Repo.preload(Delivest.Repo.reload!(order), :transitions).transitions

      assert has_element?(lv, "#order-history-#{order.id}")
      assert staff_id
    end

    test "an admin reverts the last step with a reason", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, _} = Delivest.Oms.Orders.advance_order(order, :ready, :system)
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      lv |> element("#order-revert-#{order.id}") |> render_click()
      assert has_element?(lv, "#revert-status-form")

      lv |> form("#revert-status-form", revert: %{reason: "  "}) |> render_submit()
      assert Delivest.Repo.reload!(order).status == :ready

      lv |> element("#order-revert-#{order.id}") |> render_click()
      lv |> form("#revert-status-form", revert: %{reason: "Нажали по ошибке"}) |> render_submit()

      assert Delivest.Repo.reload!(order).status == :preparing
      assert has_element?(lv, "#order-history-#{order.id} .line-through")
    end

    test "operators without the revert right see no revert", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, _} = Delivest.Oms.Orders.advance_order(order, :accepted, :system)
      conn = login(conn, ["orders.read", "orders.update"], branch)
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#order-next-#{order.id}")
      refute has_element?(lv, "#order-revert-#{order.id}")
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

    test "an order opens in the side panel", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} =
        live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders/#{order.id}")

      assert has_element?(lv, "#order-slideover-toggle[checked]")
      assert has_element?(lv, "#shown-order #order-next-#{order.id}")
      refute has_element?(lv, "#orders-#{order.id}")

      lv |> element("#order-next-#{order.id}") |> render_click()
      assert Delivest.Repo.reload!(order).status == :accepted
    end

    test "the card previews three items and opens the complete order with the same filters", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      for index <- 2..10 do
        product = insert_branch_product(branch.id, price: 100)

        item =
          Delivest.Repo.insert!(%Delivest.Oms.OrderItem{
            order_id: order.id,
            product_id: product.id,
            title: "Item #{index}",
            quantity: 1,
            price: 100
          })

        Delivest.Repo.insert!(%Delivest.Oms.OrderItemModifier{
          order_item_id: item.id,
          name: "Modifier #{index}",
          quantity: 1,
          price: 0
        })
      end

      {:ok, lv, _html} =
        live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders?period=all")

      card = "#orders-#{order.id}"
      assert has_element?(lv, "#{card} .order-card-number", "##{order.daily_number}")
      assert has_element?(lv, "#{card} .order-card-number[title='#{order.number}']")
      assert has_element?(lv, "#{card} .order-card-items li", "7 more items")
      refute has_element?(lv, "#{card} .order-card-items li:nth-child(5)")
      refute has_element?(lv, "#{card} .order-card-items", "Modifier")

      lv |> element("#order-view-#{order.id}") |> render_click()
      assert_patch(lv, ~p"/staff/b/#{branch}/orders/#{order.id}?period=all")
      assert has_element?(lv, "#shown-order .order-card-items li:nth-child(10)")
      assert has_element?(lv, "#shown-order .order-card-items", "Modifier 10")
      refute has_element?(lv, "#shown-order .order-card-number")
    end

    test "a missing order goes back to the list", %{conn: conn, branch: branch} do
      conn = login(conn, ["admin"], branch)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/staff/b/#{branch}/orders/#{Ecto.UUID.generate()}")

      assert path == ~p"/staff/b/#{branch}/orders"
    end

    test "tabs count orders and filter by status", %{conn: conn, branch: branch, order: order} do
      create_order(branch.id)
      |> Ecto.Changeset.change(status: :preparing)
      |> Delivest.Repo.update!()

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      assert has_element?(
               lv,
               "main #orders-page #orders-filters #order-status-tabs #order-status-tab-created"
             )

      assert has_element?(
               lv,
               "main #orders-page #orders-filters #order-status-tabs #order-status-tab-preparing"
             )

      render_patch(lv, ~p"/staff/b/#{branch}/orders?status=preparing")

      assert has_element?(
               lv,
               "#order-status-select",
               DelivestWeb.Staff.OrderLive.OrderHelpers.status_label(:preparing)
             )

      refute has_element?(lv, "#orders-#{order.id}")
      assert_patch(lv, ~p"/staff/b/#{branch}/orders?status=preparing")
    end

    test "cancelling asks for a reason", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      lv |> element("#order-cancel-#{order.id}") |> render_click()

      assert Delivest.Repo.reload!(order).status == :created
      assert has_element?(lv, "#cancel-order-form")

      lv
      |> form("#cancel-order-form", cancel: %{reason: "unreachable", note: "Не берёт трубку"})
      |> render_submit()

      assert %{status: :cancelled, cancel_reason: :unreachable} = Delivest.Repo.reload!(order)
      assert has_element?(lv, "#order-cancel-reason-#{order.id}", "Не берёт трубку")
    end

    test "an unmapped Frontpad status code is shown", %{conn: conn, branch: branch, order: order} do
      {:ok, _order} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "sent",
          remote_status_code: "4"
        })

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#order-unmapped-#{order.id}", "4")
      assert has_element?(lv, "#order-gateway-#{order.id}", "Frontpad")
      refute has_element?(lv, "#order-payment-#{order.id}")
    end

    test "Frontpad resend requires CRM reconciliation confirmation", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
        branch_id: branch.id,
        crm: %Delivest.Integrations.Crm.BranchSettings{
          enabled: true,
          provider: :frontpad,
          frontpad: %Delivest.Integrations.Frontpad.Settings{api_key: "key"}
        }
      })

      {:ok, _order} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "unknown",
          alert: "Check in Frontpad"
        })

      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      assert has_element?(lv, "#order-crm-resend-form-#{order.id} input[name=confirmed]")

      render_hook(lv, "crm_alert", %{"id" => order.id, "action" => "resend"})
      assert Delivest.Repo.reload!(order).crm.status == "unknown"

      lv
      |> form("#order-crm-resend-form-#{order.id}", %{confirmed: "true"})
      |> render_submit()

      assert Delivest.Repo.reload!(order).crm.status == "pending"
    end

    test "a failed unsent CRM order offers retry even without an alert", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, _} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "failed",
          last_error: "request rejected",
          alert: nil
        })

      {:ok, lv, _} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")
      assert has_element?(lv, "#order-crm-retry-unsent-#{order.id}")
    end

    test "an open order shows the closed shift, actual retry time, and clears it after success",
         %{
           conn: conn,
           branch: branch,
           order: order
         } do
      conn = login(conn, ["admin"], branch) |> Plug.Conn.put_session(:locale, "ru")
      {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/orders/#{order.id}")
      assert has_element?(lv, "#shown-order")
      branch_name = branch.name

      {:ok, updated} =
        Delivest.Oms.Orders.update_order_crm(order, %{
          provider: "frontpad",
          status: "pending",
          last_error: ~s({:frontpad, "cash_close"}),
          alert: nil
        })

      assert has_element?(
               lv,
               "#order-crm-alert-#{order.id}",
               "Frontpad отклонил заказ: кассовая смена закрыта. Откройте смену в разделе „Касса“ для филиала „#{branch_name}“"
             )

      refute has_element?(lv, "#order-crm-retry-at-#{order.id}")

      at = DateTime.add(DateTime.utc_now(), 600, :second)

      job =
        Oban.insert!(
          Delivest.Integrations.Crm.SyncWorker.new(
            %{"order_id" => order.id, "branch_id" => branch.id},
            scheduled_at: at
          )
        )

      assert eventually(fn -> has_element?(lv, "#order-crm-retry-at-#{order.id}") end)
      assert has_element?(lv, "#order-crm-retry-at-#{order.id}", "Europe/Moscow")

      assert has_element?(
               lv,
               "#order-crm-retry-at-#{order.id}",
               at |> Delivest.LocalTime.local(branch.id) |> Calendar.strftime("%d.%m %H:%M")
             )

      later = DateTime.add(at, 600, :second)
      job |> Ecto.Changeset.change(scheduled_at: later) |> Delivest.Repo.update!()

      {:ok, updated} =
        Delivest.Oms.Orders.update_order_crm(updated, %{
          attempts: 2,
          cash_close_attempts: 2,
          last_error: ~s({:frontpad, "cash_close"})
        })

      assert has_element?(
               lv,
               "#order-crm-retry-at-#{order.id}",
               later |> Delivest.LocalTime.local(branch.id) |> Calendar.strftime("%d.%m %H:%M")
             )

      {:ok, updated} =
        Delivest.Oms.Orders.update_order_crm(updated, %{
          status: "failed",
          cash_close_attempts: 7
        })

      assert has_element?(
               lv,
               "#order-crm-alert-#{order.id}",
               "Автоматические попытки отправки в Frontpad завершились."
             )

      refute has_element?(lv, "#order-crm-retry-at-#{order.id}")

      {:ok, _} =
        Delivest.Oms.Orders.update_order_crm(updated, %{
          status: "sent",
          external_id: "901",
          external_number: "17",
          last_error: nil,
          alert: nil
        })

      refute has_element?(lv, "#order-crm-alert-#{order.id}")
      assert has_element?(lv, "#shown-order", "#17")
    end

    test "an order of our own carries no gateway note", %{
      conn: conn,
      branch: branch,
      order: order
    } do
      {:ok, lv, _html} = live(login(conn, ["admin"], branch), ~p"/staff/b/#{branch}/orders")

      refute has_element?(lv, "#order-gateway-#{order.id}")
    end

    test "read-only staff cannot change orders", %{conn: conn, branch: branch, order: order} do
      {:ok, lv, _html} = live(login(conn, ["orders.read"], branch), ~p"/staff/b/#{branch}/orders")

      refute has_element?(lv, "#order-next-#{order.id}")
      refute has_element?(lv, "#order-cancel-#{order.id}")

      html = render_click(lv, "advance", %{"order-id" => order.id, "to" => "accepted"})

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

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders?period=all&page_size=1")
      assert has_element?(lv, "#orders-#{first.id}")
      refute has_element?(lv, "#orders-#{second.id}")

      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders?period=all&page_size=1&page=2")
      assert has_element?(lv, "#orders-#{second.id}")
      refute has_element?(lv, "#orders-#{first.id}")

      {:ok, lv, _html} =
        live(conn, ~p"/staff/b/#{branch}/orders?period=all&page_size=1&sort=time")

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
