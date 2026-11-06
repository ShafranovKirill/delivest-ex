defmodule Delivest.Franchise.Rating do
  use Ecto.Schema
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}

  @type t :: %__MODULE__{}

  @max_age_days 7
  @max_reviews_count 2_147_483_647

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "franchise_ratings" do
    field :provider, Ecto.Enum, values: [:yandex]
    field :rating, :float
    field :reviews_count, :integer, default: 0
    field :fetched_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def store(provider, %{rating: rating, reviews_count: count}, now \\ DateTime.utc_now(:second)) do
    Repo.insert(
      %__MODULE__{provider: provider, rating: rating, reviews_count: count, fetched_at: now},
      on_conflict: [set: [rating: rating, reviews_count: count, fetched_at: now, updated_at: now]],
      conflict_target: :provider
    )
  end

  def store_manual(staff, attrs) when is_map(attrs) do
    with true <- Identity.can?(staff, "admin") || {:error, :forbidden},
         {:ok, rating} <- parse_rating(Map.get(attrs, "rating")),
         {:ok, count} <- parse_count(Map.get(attrs, "reviews_count")),
         {:ok, saved} <- store(:yandex, %{rating: rating, reviews_count: count}) do
      Audit.record(staff, "franchise.yandex_rating_updated", :franchise,
        metadata: %{rating: rating, reviews_count: count}
      )

      {:ok, saved}
    end
  end

  def store_manual(_staff, _attrs), do: {:error, :invalid_rating}

  defp parse_rating(value) when is_number(value) and value >= 1 and value <= 5,
    do: {:ok, value / 1}

  defp parse_rating(value) when is_binary(value) do
    case Float.parse(value) do
      {rating, ""} -> valid_rating(rating)
      _ -> {:error, :invalid_rating}
    end
  end

  defp parse_rating(_value), do: {:error, :invalid_rating}

  defp valid_rating(value) when value >= 1.0 and value <= 5.0, do: {:ok, value}
  defp valid_rating(_value), do: {:error, :invalid_rating}

  defp parse_count(value)
       when is_integer(value) and value >= 0 and value <= @max_reviews_count,
       do: {:ok, value}

  defp parse_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 and count <= @max_reviews_count -> {:ok, count}
      _ -> {:error, :invalid_count}
    end
  end

  defp parse_count(_value), do: {:error, :invalid_count}

  def current(provider, now \\ DateTime.utc_now(:second)) do
    since = DateTime.add(now, -@max_age_days, :day)

    Repo.one(from(r in __MODULE__, where: r.provider == ^provider and r.fetched_at >= ^since))
  end
end
