defmodule Delivest.Integrations.YandexDelivery.Poller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.YandexDelivery

  @impl true
  def key, do: :yandex_delivery

  @impl true
  def interval, do: 10

  @impl true
  def targets, do: YandexDelivery.active_branches()

  @impl true
  def poll(branch_id) do
    case YandexDelivery.poll(branch_id) do
      {:error, {:yandex_delivery, 429, _code}} -> {:snooze, 30}
      result -> result
    end
  end
end
