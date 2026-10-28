defmodule Delivest.Integrations.YandexDelivery.PollWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Integrations.YandexDelivery.JournalWorker

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(YandexDelivery.active_branches(), &JournalWorker.enqueue/1)
  end
end
