defmodule Delivest.Net.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Net.{Branch, CategoriesBranches}

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :inserted_at],
    default_limit: 10,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:asc]
    }
  }

  schema "categories" do
    field :name, :string
    field :is_active, :boolean, default: false

    many_to_many :branches, Branch,
      join_through: CategoriesBranches,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> cast_assoc(:branches)
  end
end
