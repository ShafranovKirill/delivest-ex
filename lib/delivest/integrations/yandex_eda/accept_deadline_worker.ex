defmodule Delivest.Integrations.YandexEda.AcceptDeadlineWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Delivest.Oms.Order
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    case Repo.get(Order, order_id) do
      %Order{status: :created, branch_id: branch_id} -> Notifier.branch_changed(branch_id)
      _order -> :ok
    end
  end
end
