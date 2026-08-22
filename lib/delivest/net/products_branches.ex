defmodule Delivest.Net.ProductsBranches do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Net.{Product, Branch}

  @type t :: %__MODULE__{}
  @primary_key false

  schema "products_branches" do
    field :is_active, :boolean, default: false

    belongs_to :product, Product, primary_key: true, type: :binary_id
    belongs_to :branch, Branch, primary_key: true, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(products_branch, attrs) do
    products_branch
    |> cast(attrs, [:is_active, :product_id, :branch_id])
    |> validate_required([:is_active, :product_id, :branch_id])
    |> assoc_constraint(:product)
    |> assoc_constraint(:branch)
  end
end
