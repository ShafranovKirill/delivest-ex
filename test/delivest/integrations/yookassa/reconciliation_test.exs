defmodule Delivest.Integrations.Yookassa.ReconciliationTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Poller.Worker
  alias Delivest.Integrations.Yookassa.Api
  alias Delivest.Integrations.Yookassa.Reconciliation
  alias Delivest.Payments.Payment

  defp local_payment(branch_id, external_id) do
    order = order_fixture(branch_id)
    {:ok, _} = Delivest.Payments.sync(Repo, order)
    payment = Repo.one!(from(p in Payment, where: p.order_id == ^order.id))

    payment =
      payment
      |> Ecto.Changeset.change(provider: "yookassa", external_id: external_id)
      |> Repo.update!()

    Repo.update_all(from(p in Payment, where: p.id == ^payment.id),
      set: [updated_at: DateTime.add(DateTime.utc_now(), -2, :hour)]
    )

    Repo.reload!(payment)
  end

  test "a cursor after 50 full pages is incomplete and visible in health" do
    branch = insert(:branch)
    mismatch = local_payment(branch.id, "mismatch")
    missing = local_payment(branch.id, "missing")
    counter = start_supervised!({Agent, fn -> 0 end})
    parent = self()
    handler_id = "reconcile-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:delivest, :yookassa, :reconciliation],
        fn _, _, meta, _ ->
          send(parent, {:reconciliation_result, meta.result})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      page = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)

      items =
        for i <- 1..100 do
          if page == 1 and i == 1 do
            %{
              "id" => "mismatch",
              "status" => "succeeded",
              "amount" => Api.amount(mismatch.amount)
            }
          else
            %{"id" => "#{page}-#{i}"}
          end
        end

      Req.Test.json(conn, %{"items" => items, "next_cursor" => "cursor-#{page}"})
    end)

    assert {:error, {:incomplete, :page_limit}} = Reconciliation.poll("all")
    assert Agent.get(counter, & &1) == 50
    assert Repo.reload!(mismatch).status == :pending
    assert Repo.reload!(missing).status == :pending
    assert %{warning: warning} = Health.get(:yookassa, nil)
    assert warning =~ "reconcile_incomplete:"
    assert warning =~ "page_limit"
    refute warning =~ "cursor-50"
    assert_receive {:reconciliation_result, :incomplete}
  end

  test "the 50th page without a cursor completes and clears the warning" do
    {:ok, _} = Health.warn(:yookassa, nil, "reconcile_incomplete:previous")
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      page = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)

      body = %{"items" => for(i <- 1..100, do: %{"id" => "#{page}-#{i}"})}
      body = if page < 50, do: Map.put(body, "next_cursor", "cursor-#{page}"), else: body
      Req.Test.json(conn, body)
    end)

    assert :done = Reconciliation.poll("all")
    assert Agent.get(counter, & &1) == 50
    assert %{warning: nil} = Health.get(:yookassa, nil)
  end

  test "repeated cursors are incomplete" do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"items" => [], "next_cursor" => "repeat"})
    end)

    assert {:error, {:incomplete, :repeated_cursor}} =
             Reconciliation.poll("all")

    assert %{warning: warning} = Health.get(:yookassa, nil)
    assert warning =~ "repeated_cursor"
  end

  test "the worker cancels a deterministic incomplete scan" do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"items" => [], "next_cursor" => "repeat"})
    end)

    assert {:cancel, "yookassa reconciliation incomplete: repeated_cursor"} =
             Worker.perform(%Oban.Job{
               args: %{"poller" => "yookassa_reconcile", "target" => "all"}
             })
  end

  test "a malformed page is incomplete" do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"items" => "not a list"})
    end)

    assert {:error, {:incomplete, :invalid_page}} = Reconciliation.poll("all")
    assert %{warning: "reconcile_incomplete:invalid_page"} = Health.get(:yookassa, nil)
  end
end
