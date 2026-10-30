defmodule Delivest.Integrations.YandexEda.BusyPoller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.{Journal, YandexEda}
  alias Delivest.Integrations.YandexEda.{BusyMode, PushApi}

  @impl true
  def key, do: :yandex_eda_busy

  @impl true
  def interval, do: 300

  @impl true
  def targets, do: ["all"]

  @impl true
  def poll(_target) do
    settings = YandexEda.get_settings()

    case YandexEda.enabled_branch_ids() do
      [] ->
        :done

      branch_ids ->
        if PushApi.configured?(settings),
          do: Journal.scope([], fn -> BusyMode.sync(settings, branch_ids) end),
          else: :done
    end
  end
end
