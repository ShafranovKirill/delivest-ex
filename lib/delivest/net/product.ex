defmodule Delivest.Net.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :price, :inserted_at],
    default_limit: 10,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:asc]
    }
  }

  schema "products" do
    field :name, :string
    field :price, :integer
    field :description, :string
    field :photos, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price, :description, :photos])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
