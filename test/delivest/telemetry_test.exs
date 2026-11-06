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
    baseline =
      Repo.aggregate(
        from(j in Oban.Job, where: j.queue == "default" and j.state == "available"),
        :count
      )

    {:ok, job} =
      Oban.insert(Oban.Job.new(%{}, worker: "Delivest.TelemetryTest", queue: "default"))

    Telemetry.oban_queues()

    assert_received {[:delivest, :oban, :queue], ^ref, %{count: count},
                     %{queue: "default", state: "available"}}

    assert count == baseline + 1

    Repo.delete!(job)
    Telemetry.oban_queues()

    assert_received {[:delivest, :oban, :queue], ^ref, %{count: ^baseline},
                     %{queue: "default", state: "available"}}

    assert_received {[:delivest, :oban, :queue], ^ref, %{count: 0},
                     %{queue: "maintenance", state: "discarded"}}
  end

  test "Oban completion and exception metrics retain queue and state" do
    metrics = Telemetry.metrics()

    for event <- [:stop, :exception] do
      summary = Enum.find(metrics, &(&1.name == [:oban, :job, event, :duration]))
      counter = Enum.find(metrics, &(&1.name == [:oban, :job, event, :count]))

      assert summary.tags == [:queue, :state]
      assert counter.tags == [:queue, :state]

      metadata = %{job: %Oban.Job{queue: "crm"}, state: :retryable}
      assert summary.tag_values.(metadata) == %{queue: "crm", state: :retryable}
    end
  end

  test "backlog reports oldest eligible age and resets an empty configured queue", %{ref: ref} do
    now = DateTime.utc_now()

    eligible = fn queue ->
      Repo.aggregate(
        from(j in Oban.Job,
          where:
            j.queue == ^queue and j.state in ["available", "scheduled", "retryable"] and
              j.scheduled_at <= ^now
        ),
        :count
      )
    end

    baseline = eligible.("notifications")
    default_baseline = eligible.("default")

    {:ok, job} =
      Oban.insert(Oban.Job.new(%{}, worker: "Delivest.TelemetryTest", queue: "notifications"))

    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [scheduled_at: DateTime.add(now, -90, :second)]
    )

    Telemetry.oban_backlog()

    expected = baseline + 1

    assert_received {[:delivest, :oban, :backlog], ^ref,
                     %{count: ^expected, oldest_age_seconds: age}, %{queue: "notifications"}}

    assert age >= 90

    assert_received {[:delivest, :oban, :backlog], ^ref, %{count: ^default_baseline},
                     %{queue: "default"}}

    Repo.delete!(job)
    Telemetry.oban_backlog()

    assert_received {[:delivest, :oban, :backlog], ^ref, %{count: ^baseline},
                     %{queue: "notifications"}}
  end

  defp events do
    [
      [:delivest, :order, :status_changed],
      [:delivest, :integration, :request],
      [:delivest, :oban, :queue],
      [:delivest, :oban, :backlog]
    ]
  end
end
