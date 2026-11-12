defmodule Delivest.Popular.Entry do
  @moduledoc """
  A product pinned to the popular list of a branch, in manual mode.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "popular_products" do
    field :position, :integer, default: 0
    belongs_to :branch, Delivest.Identity.Branch
    belongs_to :product, Delivest.Net.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:branch_id, :product_id, :position])
    |> validate_required([:branch_id, :product_id])
    |> unique_constraint([:branch_id, :product_id])
  end
end
