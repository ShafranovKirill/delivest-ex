defmodule Delivest.Integrations.YandexEda.MenuReloadWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 30, states: [:available, :scheduled]]

  alias Delivest.Integrations.{Journal, YandexEda}
  alias Delivest.Integrations.YandexEda.PushApi

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"branch_id" => branch_id, "operation" => operation}}) do
    settings = YandexEda.get_settings()

    if PushApi.configured?(settings),
      do:
        Journal.scope([branch_id: branch_id], fn ->
          PushApi.reload_menu(settings, branch_id, operation)
        end),
      else: :ok
  end
end
