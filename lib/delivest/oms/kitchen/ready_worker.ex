defmodule Delivest.Oms.Kitchen.ReadyWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:order_id], period: :infinity, states: :incomplete]

  alias Delivest.Oms.Kitchen

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "staff_id" => staff_id}}) do
    case Kitchen.finish_ready(order_id, staff_id) do
      {:ok, _order} -> :ok
      {:error, reason} when is_atom(reason) -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
