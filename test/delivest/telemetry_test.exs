defmodule Delivest.TelemetryTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.HTTP.Client
  alias Delivest.Oms.Orders
  alias DelivestWeb.Telemetry

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), events())
    on_exit(fn -> :telemetry.detach(ref) end)
    %{ref: ref}
  end

  test "a status change reports from, to, source and branch", %{ref: ref} do
    branch = insert(:branch)
    order = order_fixture(branch.id)
    staff = insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    staff = Repo.preload(staff, [:role, :branches])

    assert {:ok, _order} = Orders.advance_order(order, :accepted, {:staff, staff})

    assert_received {[:delivest, :order, :status_changed], ^ref, %{count: 1},
                     %{from: :created, to: :accepted, source: :staff, branch_id: branch_id}}

    assert branch_id == branch.id
  end

  test "an integration request reports the provider, status and duration", %{ref: ref} do
    Req.Test.stub(Client, fn conn -> Req.Test.json(conn, %{}) end)

    assert {:ok, _body} =
             Client.get("/check", [], base_url: "https://example.test", journal: :zvonok)

    assert_received {[:delivest, :integration, :request], ^ref, %{count: 1, duration: duration},
                     %{provider: "zvonok", status: 200}}

    assert is_integer(duration)
  end

  test "a failed request is reported as an error", %{ref: ref} do
    Req.Test.stub(Client, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, _reason} =
             Client.get("/check", [], base_url: "https://example.test", journal: :dadata)

    assert_received {[:delivest, :integration, :request], ^ref, %{count: 1},
                     %{provider: "dadata", status: :error}}
  end

  test "the poller reports Oban queue depth", %{ref: ref} do
    {:ok, _job} =
      Oban.insert(Oban.Job.new(%{}, worker: "Delivest.TelemetryTest", queue: "default"))

    Telemetry.oban_queues()

    assert_received {[:delivest, :oban, :queue], ^ref, %{count: count},
                     %{queue: "default", state: "available"}}

    assert count >= 1
  end

  defp events do
    [
      [:delivest, :order, :status_changed],
      [:delivest, :integration, :request],
      [:delivest, :oban, :queue]
    ]
  end
end
