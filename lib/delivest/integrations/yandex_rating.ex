defmodule Delivest.Integrations.YandexRating do
  alias Delivest.Franchise
  alias Delivest.Franchise.Rating
  alias Delivest.Integrations.Health
  alias Delivest.Integrations.YandexRating.Api

  def configured?(settings \\ Franchise.get_settings()),
    do: settings.yandex_org_id not in [nil, ""] and settings.yandex_api_key not in [nil, ""]

  def refresh(settings \\ Franchise.get_settings()) do
    with true <- configured?(settings) || {:error, :yandex_rating_not_configured},
         {:ok, fetched} <- Api.fetch(settings),
         {:ok, _rating} <- Rating.store(:yandex, fetched) do
      Health.recovered(:yandex_rating, nil)
      :ok
    else
      {:error, reason} = error ->
        Health.report(:yandex_rating, nil, __MODULE__, {:error, reason})
        error
    end
  end

  def current do
    case Rating.current(:yandex) do
      nil ->
        nil

      rating ->
        %{value: rating.rating, count: rating.reviews_count, url: url(Franchise.get_settings())}
    end
  end

  def url(%{yandex_org_id: id}) when id not in [nil, ""],
    do: "https://yandex.ru/maps/org/#{id}/reviews/"

  def url(_settings), do: nil
end
