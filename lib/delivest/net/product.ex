defmodule Delivest.Net.Product do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Net.Category

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}
  @measure_units [:g, :ml]
  @excises [:sugary_drink, :other]
  @nutrients [:calories, :proteins, :fats, :carbohydrates]

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
    field :old_price, Delivest.Money.Type
    field :price, Delivest.Money.Type
    field :description, :string
    field :quantity, :integer
    field :weight, :integer
    field :measure_unit, Ecto.Enum, values: @measure_units, default: :g
    field :calories, :float
    field :proteins, :float
    field :fats, :float
    field :carbohydrates, :float
    field :excise, Ecto.Enum, values: @excises
    field :is_active, :boolean, default: true
    field :tags, {:array, :string}, default: []
    field :suggested, :boolean, default: false
    field :order, :float
    belongs_to :media, Delivest.Media.File, foreign_key: :media_id, type: :binary_id
    field :crm_ids, :map, virtual: true, default: %{}

    has_many :external_ids, Delivest.Net.ProductExternalId,
      foreign_key: :entity_id,
      where: [entity_type: "product"],
      on_replace: :delete

    belongs_to :category, Category, type: :binary_id

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def measure_units, do: @measure_units
  def excises, do: @excises
  def nutrients, do: @nutrients

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :old_price,
      :price,
      :description,
      :quantity,
      :weight,
      :measure_unit,
      :media_id,
      :is_active,
      :crm_ids,
      :category_id,
      :deleted_at,
      :slug,
      :tags,
      :suggested,
      :excise
      | @nutrients
    ])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0, less_than: 100_000_000)
    |> validate_number(:old_price, greater_than: 0, less_than: 100_000_000)
    |> validate_nutrients()
    |> update_change(:slug, &Delivest.Slug.slugify/1)
    |> validate_length(:slug, max: 80)
    |> unique_constraint(:slug)
  end

  defp validate_nutrients(changeset) do
    Enum.reduce(@nutrients, changeset, fn field, acc ->
      validate_number(acc, field, greater_than_or_equal_to: 0, less_than: 10_000)
    end)
  end
end
