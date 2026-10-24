defmodule Delivest.Push.Worker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 5, keys: [:order_id], states: [:available, :scheduled]]

  alias Delivest.Push.Dispatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}), do: Dispatch.run(order_id)
end
