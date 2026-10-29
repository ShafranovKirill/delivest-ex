defmodule Delivest.Integrations.Poller.Worker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:poller, :target], states: [:available, :scheduled]]

  alias Delivest.Integrations.Poller

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"poller" => key, "target" => target}}) do
    with {:ok, module} <- Poller.fetch(key) do
      case module.poll(target) do
        :done -> :ok
        {:ok, _result} -> :ok
        :more -> next(module, target, module.interval())
        {:snooze, seconds} -> next(module, target, seconds)
        {:error, _reason} = error -> error
      end
    end
  end

  def perform(%Oban.Job{args: %{"poller" => key}}) do
    with {:ok, module} <- Poller.fetch(key), do: Poller.enqueue_all(module)
  end

  defp next(module, target, seconds) do
    {:ok, _job} = Poller.enqueue(module, target, schedule_in: seconds)
    :ok
  end
end
