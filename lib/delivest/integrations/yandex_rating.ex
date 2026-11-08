defmodule Delivest.Integrations.YandexRating do
  alias Delivest.Franchise.Rating
  alias Delivest.Integrations.Health
  alias Delivest.Integrations.YandexRating.Api

  def refresh do
    with {:ok, fetched} <- Api.fetch(),
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
        %{value: rating.rating, count: rating.reviews_count, url: nil}
    end
  end
end
