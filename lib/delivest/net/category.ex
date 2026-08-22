defmodule Delivest.Net.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Net.{Branch}

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
    field :order, :float
    field :is_active, :boolean
    belongs_to :branch, Branch, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :order, :branch_id, :is_active])
    |> validate_required([:name, :branch_id])
    |> assoc_constraint(:branch)
  end
end
