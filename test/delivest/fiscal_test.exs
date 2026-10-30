defmodule Delivest.FiscalTest do
  use DelivestWeb.ConnCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Fiscal
  alias Delivest.Fiscal.{BranchSettings, PollWorker, Receipt, RegisterWorker}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.AtolOnline
  alias Delivest.{Payments, Repo}

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      fiscal: %BranchSettings{
        mode: :own,
        inn: "5544332219",
        sno: :usn_income,
        payment_address: "https://v5.online.atol.ru",
        email: "chek@pizza.ru",
        atol: %AtolOnline.Settings{
          login: "login-#{branch.id}",
          password: "secret",
          group_code: "group",
          sandbox: true,
          callback_token: "cb-token"
        }
      }
    })

    order = order_fixture(branch.id, price: 59_000)
    %{order: order, payments: Payments.list(order.id)}
  end

  defp stub_atol(sell) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      cond do
        String.ends_with?(conn.request_path, "getToken") ->
          Req.Test.json(conn, %{"token" => "tok"})

        String.contains?(conn.request_path, "/report/") ->
          Req.Test.json(conn, %{
            "uuid" => "u-1",
            "status" => "done",
            "payload" => %{"fn_number" => "1"}
          })

        true ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(self(), {:atol_body, Jason.decode!(body)})
          sell.(conn)
      end
    end)
  end

  defp register(receipt), do: perform_job(RegisterWorker, %{"receipt_id" => receipt.id})

  test "a receipt is registered, then confirmed by the callback", %{
    conn: conn,
    order: order,
    payments: payments
  } do
    stub_atol(&Req.Test.json(&1, %{"uuid" => "u-1", "status" => "wait"}))

    assert {:ok, %Receipt{status: :pending, kind: :sell, amount: 59_000} = receipt} =
             Fiscal.issue(order, payments, cashier: "Иван")

    assert_enqueued(worker: RegisterWorker, args: %{"receipt_id" => receipt.id})
    assert :ok = register(receipt)

    assert_received {:atol_body, %{"external_id" => id, "receipt" => body}}
    assert id == receipt.id

    assert %{"total" => 590, "payments" => [%{"type" => 0, "sum" => 590}], "cashier" => "Иван"} =
             body

    assert %Receipt{status: :wait, uuid: "u-1"} = Fiscal.get(receipt.id)
    assert_enqueued(worker: PollWorker, args: %{"receipt_id" => receipt.id})

    conn
    |> post("/integrations/fiscal/atol/wrong", %{"uuid" => "u-1", "status" => "done"})
    |> json_response(404)

    conn
    |> post("/integrations/fiscal/atol/cb-token", %{
      "uuid" => "u-1",
      "status" => "done",
      "payload" => %{"ofd_receipt_url" => "https://ofd/1"}
    })
    |> json_response(200)

    assert %Receipt{status: :done} = done = Fiscal.get(receipt.id)
    assert Receipt.ofd_url(done) == "https://ofd/1"
    assert [%{fiscalized_by: :us}] = Payments.list(order.id)
  end

  test "the poll picks up the result", %{order: order, payments: payments} do
    stub_atol(&Req.Test.json(&1, %{"uuid" => "u-1", "status" => "wait"}))
    {:ok, receipt} = Fiscal.issue(order, payments)
    :ok = register(receipt)

    assert :ok = perform_job(PollWorker, %{"receipt_id" => receipt.id})
    assert %Receipt{status: :done, payload: %{"fn_number" => "1"}} = Fiscal.get(receipt.id)
  end

  test "a validation error fails the receipt and it can be retried", %{
    order: order,
    payments: payments
  } do
    stub_atol(fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"error" => %{"code" => 32, "text" => "bad"}, "status" => "fail"})
    end)

    {:ok, receipt} = Fiscal.issue(order, payments)
    assert {:cancel, {:atol, 32, "bad"}} = register(receipt)
    assert %Receipt{status: :fail} = failed = Fiscal.get(receipt.id)

    staff = insert(:staff)
    assert {:ok, %Receipt{status: :pending, request: request}} = Fiscal.retry(failed, staff)
    assert request == failed.request
    assert [_failed, _retry] = Fiscal.list(order.id)
  end

  test "a done receipt is refunded once", %{order: order, payments: payments} do
    stub_atol(&Req.Test.json(&1, %{"uuid" => "u-#{System.unique_integer()}", "status" => "done"}))
    {:ok, receipt} = Fiscal.issue(order, payments)
    :ok = register(receipt)

    staff = insert(:staff)
    done = Fiscal.get(receipt.id)

    assert {:ok, %Receipt{kind: :sell_refund, amount: 59_000, refund_of_id: refund_of}} =
             Fiscal.refund(done, staff)

    assert refund_of == receipt.id
    assert {:error, :already_refunded} = Fiscal.refund(done, staff)
  end

  test "branches without own fiscalization issue nothing", %{payments: payments} do
    other = insert(:branch)
    order = order_fixture(other.id)
    assert {:error, :not_own} = Fiscal.issue(order, payments)
  end

  test "completing the order issues a receipt per cash payment", %{order: order} do
    staff = insert(:staff, name: "Мария", role: build(:role, permissions: ["admin"]))

    {:ok, order} =
      Enum.reduce([:accepted, :preparing, :ready, :completed], {:ok, order}, fn status,
                                                                                {:ok, o} ->
        Delivest.Oms.Orders.advance_order(o, status, {:staff, staff})
      end)

    deliver_events()
    assert [%Receipt{kind: :sell, status: :pending, request: request}] = Fiscal.list(order.id)
    assert request["receipt"]["cashier"] == "Мария"

    assert_enqueued(worker: RegisterWorker)
    assert [] = Fiscal.OrderSubscriber.payments(order, Fiscal.settings(order.branch_id))
  end

  test "the order card retries a failed receipt", %{conn: conn, order: order, payments: payments} do
    import Phoenix.LiveViewTest

    stub_atol(fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"error" => %{"code" => 32, "text" => "bad"}, "status" => "fail"})
    end)

    {:ok, receipt} = Fiscal.issue(order, payments)
    register(receipt)

    staff = insert(:staff, role: insert(:role, permissions: ["orders.read", "orders.update"]))

    branch = Repo.get!(Delivest.Identity.Branch, order.branch_id)
    insert(:staff_branch, staff: staff, branch: branch)

    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/orders")
    assert lv |> element("#receipt-#{receipt.id}") |> render() =~ "32: bad"

    lv |> element("#receipt-#{receipt.id} button[phx-click=retry_receipt]") |> render_click()
    assert [_failed, %Receipt{status: :pending}] = Fiscal.list(order.id)
  end
end
