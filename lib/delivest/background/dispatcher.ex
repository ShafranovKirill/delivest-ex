defmodule Delivest.Background.Dispatcher do
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  @impl Oban.Worker
  def perform(_job) do
    Delivest.Background.dispatch_due()
    :ok
  end
end
