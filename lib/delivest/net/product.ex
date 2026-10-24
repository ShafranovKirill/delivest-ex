defmodule Delivest.Net.Product do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Net.Category

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}
  @tags [:hit, :new, :spicy, :vegetarian]

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
    field :slug, :string
    field :old_price, :string
    field :price, :integer
    field :description, :string
    field :quantity, :integer
    field :weight, :integer
    field :is_active, :boolean, default: true
    field :tags, {:array, Ecto.Enum}, values: @tags, default: []
    field :order, :float
    belongs_to :media, Delivest.Media.File, foreign_key: :media_id, type: :binary_id
    field :external_id, :string

    belongs_to :category, Category, type: :binary_id

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def tags, do: @tags

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :old_price,
      :price,
      :description,
      :quantity,
      :weight,
      :media_id,
      :is_active,
      :external_id,
      :category_id,
      :deleted_at,
      :slug,
      :tags
    ])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> update_change(:slug, &Delivest.Slug.slugify/1)
    |> validate_length(:slug, max: 80)
    |> unique_constraint(:slug)
  end
end
