defmodule Delivest.Integrations.YandexRatingTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

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

  test "manual rating requires admin and validates exact SQL-safe values" do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    operator = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))

    assert {:error, :forbidden} =
             Rating.store_manual(operator, %{"rating" => "4.5", "reviews_count" => "10"})

    for attrs <- [
          %{"rating" => "0.9", "reviews_count" => "10"},
          %{"rating" => "5.1", "reviews_count" => "10"},
          %{"rating" => "4.5x", "reviews_count" => "10"},
          %{"rating" => "4.5", "reviews_count" => "-1"},
          %{"rating" => "4.5", "reviews_count" => "2147483648"},
          %{"rating" => "4.5", "reviews_count" => "999999999999999999999999999999999999"}
        ] do
      assert {:error, _reason} = Rating.store_manual(admin, attrs)
    end

    assert {:error, :invalid_rating} = Rating.store_manual(admin, "not a form")

    assert {:error, :invalid_rating} =
             Rating.store_manual(admin, %{"rating" => 10 ** 1_000, "reviews_count" => "10"})

    assert Repo.all(Rating) == []

    assert {:ok, _} =
             Rating.store_manual(admin, %{"rating" => "4.5", "reviews_count" => "10"})

    assert %{value: 4.5, count: 10} = YandexRating.current()

    assert %{actor_id: actor_id, action: "franchise.yandex_rating_updated"} =
             Repo.one!(Delivest.Audit.Event)

    assert actor_id == admin.id
  end
end
