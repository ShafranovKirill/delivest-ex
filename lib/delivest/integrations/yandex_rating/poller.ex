defmodule Delivest.Integrations.YandexRating.Poller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.YandexRating

  @impl true
  def key, do: :yandex_rating

  @impl true
  def interval, do: 86_400

  @impl true
  def targets, do: if(YandexRating.configured?(), do: ["all"], else: [])

  @impl true
  def poll(_target) do
    case YandexRating.refresh() do
      :ok -> :done
      {:error, _reason} = error -> error
    end
  end
end
