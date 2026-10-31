defmodule Delivest.Franchise.Rating do
  use Ecto.Schema
  import Ecto.Query

  alias Delivest.Repo

  @type t :: %__MODULE__{}

  @max_age_days 7

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

  def current(provider, now \\ DateTime.utc_now(:second)) do
    since = DateTime.add(now, -@max_age_days, :day)

    Repo.one(from(r in __MODULE__, where: r.provider == ^provider and r.fetched_at >= ^since))
  end
end
