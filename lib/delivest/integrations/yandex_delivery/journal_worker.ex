defmodule Delivest.Integrations.YandexDelivery.JournalWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 60, keys: [:branch_id], states: [:available, :scheduled]]

  alias Delivest.Integrations.YandexDelivery

  @interval 10

  def enqueue(branch_id, opts \\ []),
    do: %{branch_id: branch_id} |> new(opts) |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id}}) do
    case YandexDelivery.poll(branch_id) do
      :done -> :ok
      :more -> next(branch_id)
      {:error, {:yandex_delivery, 429, _code}} -> next(branch_id, 30)
      {:error, reason} -> {:error, reason}
    end
  end

  defp next(branch_id, seconds \\ @interval) do
    {:ok, _job} = enqueue(branch_id, schedule_in: seconds)
    :ok
  end
end
