defmodule Delivest.Background.Dispatcher do
  use Oban.Worker, queue: :background, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    Delivest.Background.dispatch_due()
    :ok
  end
end
