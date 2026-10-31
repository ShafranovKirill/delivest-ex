defmodule Delivest.Integrations.YandexRatingTest do
  use Delivest.DataCase, async: true

  alias Delivest.Franchise.Rating
  alias Delivest.Integrations.YandexRating
  alias Delivest.Integrations.YandexRating.Poller

  defp settings(attrs \\ %{}),
    do: Map.merge(%Delivest.Franchise.Settings{yandex_org_id: "123", yandex_api_key: "k"}, attrs)

  test "nothing is configured, nothing is polled" do
    refute YandexRating.configured?(settings(%{yandex_api_key: nil}))

    assert {:error, :yandex_rating_not_configured} =
             YandexRating.refresh(settings(%{yandex_org_id: nil}))

    assert YandexRating.current() == nil
  end

  test "a refresh stores the rating and a second one overwrites it" do
    assert :ok = YandexRating.refresh(settings())
    assert {:ok, _} = Rating.store(:yandex, %{rating: 4.1, reviews_count: 7})
    assert %{rating: 4.1, reviews_count: 7} = Rating.current(:yandex)
    assert [_] = Delivest.Repo.all(Rating)
  end

  test "stale data is not served" do
    old = DateTime.add(DateTime.utc_now(:second), -8, :day)
    {:ok, _} = Rating.store(:yandex, %{rating: 4.1, reviews_count: 7}, old)
    assert Rating.current(:yandex) == nil
  end

  test "the poller has no targets without settings" do
    assert Poller.targets() == []
  end
end
