defmodule DelivestWeb.Telemetry do
  use Supervisor
  import Ecto.Query
  import Telemetry.Metrics

  alias Delivest.Repo

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("delivest.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("delivest.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("delivest.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("delivest.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("delivest.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Orders: how fast they move and how long each stage takes
      counter("delivest.order.status_changed.count",
        tags: [:from, :to, :source],
        description: "Orders that moved between statuses"
      ),
      summary("delivest.order.stage_duration.duration",
        unit: :millisecond,
        tags: [:stage],
        description: "Time an order spent in the stage it left"
      ),

      # Integrations: latency and errors by provider
      summary("delivest.integration.request.duration",
        unit: :millisecond,
        tags: [:provider, :status],
        description: "Time an external provider took to answer"
      ),
      counter("delivest.integration.request.count",
        tags: [:provider, :status],
        description: "External provider requests"
      ),
      counter("delivest.yookassa.reconciliation.count",
        tags: [:result],
        description: "YooKassa reconciliation runs by completion result"
      ),

      # Outbox: subscriber lag and delivery rate
      summary("delivest.outbox.delivered.lag",
        unit: :millisecond,
        tags: [:subscriber],
        description: "Time from recording a domain event to delivering it"
      ),
      counter("delivest.outbox.delivered.count",
        tags: [:subscriber],
        description: "Domain events delivered to subscribers"
      ),

      # CRM: delivery outcomes and retries
      counter("delivest.crm.sync.count",
        tags: [:provider, :result, :attempt],
        description: "Order deliveries to a CRM by outcome"
      ),

      # Oban: depth of every queue by state
      last_value("delivest.oban.queue.count",
        tags: [:queue, :state],
        description: "Jobs waiting in an Oban queue"
      )
    ]
  end

  @doc """
  Reports Oban queue depth for the dashboard.

  Runs from the telemetry poller, so the value is a snapshot that the dashboard
  shows as the current queue depth rather than a growing sum.
  """
  def oban_queues do
    Oban.Job
    |> group_by([j], [j.queue, j.state])
    |> select([j], {j.queue, j.state, count(j.id)})
    |> Repo.all()
    |> Enum.each(fn {queue, state, count} ->
      :telemetry.execute(
        [:delivest, :oban, :queue],
        %{count: count},
        %{queue: queue, state: state}
      )
    end)
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :oban_queues, []}
    ]
  end
end
