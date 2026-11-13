defmodule Delivest.Integrations.YandexEda.MenuReloadWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 30, states: [:available, :scheduled]]

  alias Delivest.Integrations.{Journal, YandexEda}
  alias Delivest.Integrations.YandexEda.PushApi

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"branch_id" => branch_id, "operation" => operation, "generation" => generation}
      })
      when is_integer(generation) do
    settings = YandexEda.get_settings()

    if current?(branch_id, generation) and PushApi.configured?(settings),
      do:
        Journal.scope([branch_id: branch_id], fn ->
          if current?(branch_id, generation),
            do: PushApi.reload_menu(settings, branch_id, operation),
            else: {:cancel, :disabled}
        end),
      else: {:cancel, :disabled}
  end

  def perform(_job), do: {:cancel, :stale_configuration}

  defp current?(branch_id, generation) do
    current = YandexEda.get_branch_settings(branch_id)
    current.enabled and current.generation == generation
  end
end
