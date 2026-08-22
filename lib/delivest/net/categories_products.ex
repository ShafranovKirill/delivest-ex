defmodule Delivest.Net.CategoriesProducts do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Net.{Category, Product}

  @type t :: %__MODULE__{}
  @primary_key false

  schema "categories_products" do
    belongs_to :category, Category, primary_key: true, type: :binary_id
    belongs_to :product, Product, primary_key: true, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(categories_products, attrs) do
    categories_products
    |> cast(attrs, [:category_id, :product_id])
    |> validate_required([:category_id, :product_id])
    |> assoc_constraint(:category)
    |> assoc_constraint(:product)
  end
end
