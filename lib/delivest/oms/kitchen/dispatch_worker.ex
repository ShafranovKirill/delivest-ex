defmodule Delivest.Oms.Kitchen.DispatchWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Delivest.Oms.Kitchen

  @impl Oban.Worker
  def perform(_job) do
    Kitchen.dispatch_due()
    :ok
  end
end
