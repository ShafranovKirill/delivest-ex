defmodule Delivest.Net.ProductStop do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "product_stops" do
    belongs_to :product, Delivest.Net.Product
    field :branch_id, :binary_id
    field :source, :string
    field :until, :utc_datetime
    field :staff_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def manual, do: "manual"

  def manual?(%__MODULE__{source: source}), do: source == manual()
end
