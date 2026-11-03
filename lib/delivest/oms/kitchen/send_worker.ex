defmodule Delivest.Oms.Kitchen.SendWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:order_id], period: :infinity, states: :incomplete]

  alias Delivest.Oms.Kitchen

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}), do: Kitchen.send_due(order_id)
end
