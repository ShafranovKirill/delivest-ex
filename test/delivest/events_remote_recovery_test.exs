defmodule Delivest.EventsRemoteRecoveryTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Couriers.Delivery, as: CourierDelivery
  alias Delivest.Events.{DeliverWorker, Event}
  alias Delivest.Fiscal.{BranchSettings, Receipt, RegisterWorker}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.AtolOnline
  alias Delivest.Integrations.Yookassa
  alias Delivest.Integrations.YandexDelivery.Settings
  alias Delivest.Oms.Order
  alias Delivest.Payments
  alias Delivest.Payments.Payment

  test "Yandex courier remote success survives a worker kill before delivery commit" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> courier_recovery_case() end)
  end

  defp courier_recovery_case do
    suffix = System.unique_integer([:positive])

    branch =
      insert(:branch,
        name: "Центральный #{suffix}",
        slug: "s3-courier-#{suffix}",
        code: "S3#{suffix}"
      )

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      city: "Тюмень",
      address: "ул Ленина, 1",
      latitude: 57.15,
      longitude: 65.53,
      phone_number: "+73452000000",
      couriers: %{source: :yandex, search: :preparing},
      yandex_delivery: %Settings{token: "local-test-token", contact_email: "kitchen@example.com"}
    })

    phone =
      "+7" <> String.pad_leading(Integer.to_string(System.unique_integer([:positive])), 10, "0")

    client = insert(:client, phone: phone, name: "Анна")

    order =
      branch.id
      |> order_fixture(price: 30_000, quantity: 2)
      |> Ecto.Changeset.change(
        fulfillment_type: :delivery,
        status: :preparing,
        client_id: client.id,
        customer_phone: client.phone,
        customer_name: client.name,
        total_amount: 60_000,
        address: %Order.Address{
          city: "Тюмень",
          street: "ул Республики",
          house: "10",
          latitude: 57.1,
          longitude: 65.5
        }
      )
      |> Repo.update!()

    event =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"to" => "preparing"}
      })

    {:ok, job} = Oban.insert(DeliverWorker.new(%{event_id: event.id, subscriber: "couriers"}))
    job = Repo.reload!(job)

    product_id =
      order |> Repo.preload(:items) |> Map.fetch!(:items) |> hd() |> Map.fetch!(:product_id)

    calls = start_supervised!({Agent, fn -> [] end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      if String.ends_with?(conn.request_path, "/claims/create") do
        request_id = conn.query_params["request_id"]
        Agent.update(calls, &[request_id | &1])
        Req.Test.json(conn, %{"id" => "claim-#{request_id}", "status" => "new", "version" => 1})
      else
        Req.Test.json(conn, %{})
      end
    end)

    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Process.put(:s3_barrier, true)

          receive do
            :go -> DeliverWorker.perform(%{job | attempt: 1})
          end
        end)
      end)

    handler = "s3-courier-kill-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if Process.get(:s3_barrier) and
               String.contains?(metadata.query || "", "UPDATE \"event_deliveries\"") do
            send(parent, {:before_commit, self()})

            receive do
              :release -> :ok
            end
          end
        end,
        nil
      )

    try do
      :ok = Req.Test.allow(Delivest.HTTP.Client, self(), pid)
      send(pid, :go)
      assert_receive {:before_commit, ^pid}, 5_000
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
      :telemetry.detach(handler)

      assert Repo.get_by(CourierDelivery, order_id: order.id) == nil
      assert :ok = DeliverWorker.perform(%{job | attempt: 2})

      assert %CourierDelivery{id: id, external_id: external_id} =
               Repo.get_by(CourierDelivery, order_id: order.id)

      assert id == event.id
      assert external_id == "claim-#{event.id}"
      assert Agent.get(calls, &Enum.reverse/1) == [event.id, event.id]
    after
      Process.exit(pid, :kill)
      :telemetry.detach(handler)
      cleanup_courier_fixture(job, order, product_id, client, branch)
    end
  end

  defp cleanup_courier_fixture(job, order, product_id, client, branch) do
    Repo.query!("DELETE FROM oban_jobs WHERE id = $1", [job.id])

    Repo.query!(
      "DELETE FROM integration_requests WHERE branch_id::text = $1 OR order_id::text = $2",
      [branch.id, order.id]
    )

    cleanup_scoped_background(order, branch)
    Repo.query!("DELETE FROM domain_events WHERE aggregate_id::text = $1", [order.id])
    Repo.delete!(order)
    if order.cart_id, do: Repo.query!("DELETE FROM carts WHERE id::text = $1", [order.cart_id])

    Repo.query!("DELETE FROM entity_relations WHERE from_id::text = $1 OR to_id::text = $2", [
      branch.id,
      product_id
    ])

    Repo.query!("DELETE FROM products WHERE id::text = $1", [product_id])
    Repo.query!("DELETE FROM clients WHERE id::text = $1", [client.id])
    Repo.query!("DELETE FROM branch_info WHERE branch_id::text = $1", [branch.id])
    Repo.delete!(branch)
  end

  test "ATOL success before a killed receipt worker is found by the stable external id on retry" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> fiscal_recovery_case() end)
  end

  defp fiscal_recovery_case do
    suffix = System.unique_integer([:positive])

    branch =
      insert(:branch,
        name: "S3 fiscal #{suffix}",
        slug: "s3-fiscal-#{suffix}",
        code: "F3#{suffix}"
      )

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      fiscal: %BranchSettings{
        mode: :own,
        inn: "5544332219",
        sno: :usn_income,
        payment_address: "https://v5.online.atol.ru",
        email: "chek@pizza.ru",
        atol: %AtolOnline.Settings{
          login: "s3-#{suffix}",
          password: "secret",
          group_code: "group",
          sandbox: true,
          callback_token: "cb-token"
        }
      }
    })

    order =
      branch.id
      |> order_fixture(price: 59_000)
      |> Ecto.Changeset.change(status: :completed)
      |> Repo.update!()

    product_id =
      order |> Repo.preload(:items) |> Map.fetch!(:items) |> hd() |> Map.fetch!(:product_id)

    [payment] = Payments.list(order.id)
    payment |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
    clear_prior_events(order.id)

    event =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"to" => "completed"}
      })

    {:ok, delivery_job} =
      Oban.insert(DeliverWorker.new(%{event_id: event.id, subscriber: "fiscal"}))

    delivery_job = Repo.reload!(delivery_job)
    kill_delivery_before_commit(delivery_job)
    assert Repo.all(Ecto.Query.from(r in Receipt, where: r.order_id == ^order.id)) == []
    assert :ok = DeliverWorker.perform(%{delivery_job | attempt: 2})

    assert [%Receipt{status: :pending} = receipt] =
             Repo.all(Ecto.Query.from(r in Receipt, where: r.order_id == ^order.id))

    parent = self()
    calls = start_supervised!({Agent, fn -> [] end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      if String.ends_with?(conn.request_path, "getToken") do
        Req.Test.json(conn, %{"token" => "tok"})
      else
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        external_id = Jason.decode!(raw)["external_id"]
        previous = Agent.get_and_update(calls, fn ids -> {length(ids), [external_id | ids]} end)

        if previous == 0 do
          send(parent, {:atol_accepted, self(), external_id})

          receive do
            :release -> :ok
          end

          Req.Test.json(conn, %{"uuid" => "u-#{suffix}", "status" => "wait"})
        else
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{
            "uuid" => "u-#{suffix}",
            "error" => %{"code" => 33, "text" => "exists", "type" => "system"}
          })
        end
      end
    end)

    {pid, monitor} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          receive do
            :go ->
              RegisterWorker.perform(%Oban.Job{
                args: %{"receipt_id" => receipt.id},
                attempt: 1,
                max_attempts: 8
              })
          end
        end)
      end)

    try do
      :ok = Req.Test.allow(Delivest.HTTP.Client, self(), pid)
      send(pid, :go)
      assert_receive {:atol_accepted, ^pid, external_id}, 5_000
      assert external_id == receipt.id
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
      assert %Receipt{status: :pending} = Repo.get!(Receipt, receipt.id)

      assert :ok =
               RegisterWorker.perform(%Oban.Job{
                 args: %{"receipt_id" => receipt.id},
                 attempt: 2,
                 max_attempts: 8
               })

      assert %Receipt{status: :wait, uuid: uuid} = Repo.get!(Receipt, receipt.id)
      assert uuid == "u-#{suffix}"
      assert Agent.get(calls, &Enum.reverse/1) == [receipt.id, receipt.id]

      assert [%Receipt{}] =
               Repo.all(Ecto.Query.from(r in Receipt, where: r.order_id == ^order.id))
    after
      Process.exit(pid, :kill)
      cleanup_fiscal_fixture(order, product_id, branch)
    end
  end

  defp cleanup_fiscal_fixture(order, product_id, branch) do
    Repo.query!(
      """
      DELETE FROM integration_requests WHERE provider = 'atol'
        AND request::jsonb->>'external_id' IN
          (SELECT COALESCE(external_id, id::text) FROM fiscal_receipts WHERE order_id::text = $1)
      """,
      [order.id]
    )

    Repo.query!(
      "DELETE FROM oban_jobs WHERE args->>'receipt_id' IN (SELECT id::text FROM fiscal_receipts WHERE order_id::text = $1)",
      [order.id]
    )

    Repo.query!("DELETE FROM fiscal_receipts WHERE order_id::text = $1", [order.id])
    cleanup_scoped_background(order, branch)
    Repo.query!("DELETE FROM domain_events WHERE aggregate_id::text = $1", [order.id])
    Repo.delete!(order)
    if order.cart_id, do: Repo.query!("DELETE FROM carts WHERE id::text = $1", [order.cart_id])

    Repo.query!("DELETE FROM entity_relations WHERE from_id::text = $1 OR to_id::text = $2", [
      branch.id,
      product_id
    ])

    Repo.query!("DELETE FROM products WHERE id::text = $1", [product_id])
    Repo.query!("DELETE FROM branch_info WHERE branch_id::text = $1", [branch.id])
    Repo.delete!(branch)
  end

  defp cleanup_scoped_background(order, branch) do
    Repo.query!(
      """
      DELETE FROM oban_jobs WHERE args->>'branch_id' = $1 OR args->>'target' = $1
        OR args->>'order_id' = $2
        OR args->>'event_id' IN (SELECT id::text FROM domain_events WHERE aggregate_id::text = $2)
        OR args->>'id' IN (SELECT id::text FROM domain_events WHERE aggregate_id::text = $2)
        OR args->>'delivery_id' IN (SELECT id::text FROM deliveries WHERE order_id::text = $2)
      """,
      [branch.id, order.id]
    )

    Repo.query!("DELETE FROM audit_events WHERE branch_id::text = $1 OR subject_id::text = $2", [
      branch.id,
      order.id
    ])

    Repo.query!("DELETE FROM order_counters WHERE branch_id::text = $1", [branch.id])
  end

  defp clear_prior_events(order_id) do
    Repo.query!(
      "DELETE FROM oban_jobs WHERE args->>'event_id' IN (SELECT id::text FROM domain_events WHERE aggregate_id::text = $1)",
      [order_id]
    )

    Repo.query!("DELETE FROM domain_events WHERE aggregate_id::text = $1", [order_id])
  end

  defp kill_delivery_before_commit(job) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Process.put(:s3_delivery_barrier, true)

          receive do
            :go -> DeliverWorker.perform(%{job | attempt: 1})
          end
        end)
      end)

    handler = "s3-delivery-kill-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if Process.get(:s3_delivery_barrier) and
               String.contains?(metadata.query || "", "UPDATE \"event_deliveries\"") do
            send(parent, {:delivery_before_commit, self()})

            receive do
              :release -> :ok
            end
          end
        end,
        nil
      )

    try do
      send(pid, :go)
      assert_receive {:delivery_before_commit, ^pid}, 5_000
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
    after
      Process.exit(pid, :kill)
      :telemetry.detach(handler)
    end
  end

  test "YooKassa capture uses the same payment key after remote success and local worker kill" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> payment_recovery_case() end)
  end

  defp payment_recovery_case do
    suffix = System.unique_integer([:positive])

    branch =
      insert(:branch,
        name: "S3 payment #{suffix}",
        slug: "s3-payment-#{suffix}",
        code: "P3#{suffix}"
      )

    order =
      branch.id
      |> order_fixture(price: 30_000)
      |> Ecto.Changeset.change(status: :accepted)
      |> Repo.update!()

    product_id =
      order |> Repo.preload(:items) |> Map.fetch!(:items) |> hd() |> Map.fetch!(:product_id)

    [payment] = Payments.list(order.id)

    payment =
      payment
      |> Ecto.Changeset.change(
        method: :online,
        status: :authorized,
        provider: "yookassa",
        external_id: "pay-#{suffix}"
      )
      |> Repo.update!()

    settings =
      Repo.insert!(%Yookassa.Settings{
        shop_id: "1",
        secret_key: "local-secret",
        webhook_token: "t"
      })

    clear_prior_events(order.id)

    event =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id,
        payload: %{"to" => "accepted"}
      })

    {:ok, job} = Oban.insert(DeliverWorker.new(%{event_id: event.id, subscriber: "payments"}))
    job = Repo.reload!(job)
    calls = start_supervised!({Agent, fn -> [] end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      key =
        conn.req_headers
        |> Enum.find_value(fn {name, value} -> if name == "idempotence-key", do: value end)

      Agent.update(calls, &[key | &1])

      Req.Test.json(conn, %{
        "id" => payment.external_id,
        "status" => "succeeded",
        "amount" => Yookassa.Api.amount(payment.amount)
      })
    end)

    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Process.put(:s3_payment_barrier, true)

          receive do
            :go -> DeliverWorker.perform(%{job | attempt: 1})
          end
        end)
      end)

    handler = "s3-payment-kill-#{suffix}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if Process.get(:s3_payment_barrier) and
               String.contains?(metadata.query || "", "UPDATE \"order_payments\"") do
            send(parent, {:payment_before_commit, self()})

            receive do
              :release -> :ok
            end
          end
        end,
        nil
      )

    try do
      :ok = Req.Test.allow(Delivest.HTTP.Client, self(), pid)
      send(pid, :go)
      assert_receive {:payment_before_commit, ^pid}, 5_000
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
      :telemetry.detach(handler)
      assert %Payment{status: :authorized} = Repo.reload!(payment)
      assert :ok = DeliverWorker.perform(%{job | attempt: 2})
      assert %Payment{status: :paid} = Repo.reload!(payment)

      assert Agent.get(calls, &Enum.reverse/1) == [
               "#{payment.id}:capture",
               "#{payment.id}:capture"
             ]

      assert :ok = DeliverWorker.perform(%{job | attempt: 3})
      assert Agent.get(calls, &length/1) == 2
    after
      Process.exit(pid, :kill)
      :telemetry.detach(handler)
      Repo.delete!(settings)

      Repo.query!(
        "DELETE FROM integration_requests WHERE provider = 'yookassa' AND url LIKE $1",
        ["%/payments/#{payment.external_id}/capture"]
      )

      cleanup_fiscal_fixture(order, product_id, branch)
    end
  end
end
