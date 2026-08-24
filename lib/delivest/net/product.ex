defmodule Delivest.Net.Product do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Net.Category

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {
    Flop.Schema,
    filterable: [:name, :category_id, :is_active],
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
    field :is_active, :boolean
    field :media_id, :binary_id
    field :external_id, :string

    belongs_to :category, Category, type: :binary_id

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :price,
      :description,
      :media_id,
      :is_active,
      :external_id,
      :category_id,
      :deleted_at
    ])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
