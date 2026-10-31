defmodule Delivest.Integrations.YandexRating.Api do
  @spec fetch(map()) ::
          {:ok, %{rating: float(), reviews_count: non_neg_integer()}} | {:error, term()}
  def fetch(_settings) do
    if Application.get_env(:delivest, :yandex_rating_stub, false),
      do: {:ok, %{rating: 4.8, reviews_count: 120}},
      else: {:error, {:yandex_rating, :not_supported}}
  end
end
