defmodule Delivest.Loyalty.ExpireWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    {:ok, Delivest.Loyalty.expire_due()}
  end
end
