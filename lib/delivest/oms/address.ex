defmodule Delivest.Oms.Address do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :city, :string
    field :street, :string
    field :house, :string
    field :apartment, :string
    field :floor, :string
    field :entrance, :string
    field :intercom, :string
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, [:city, :street, :house, :apartment, :floor, :entrance, :intercom])
    |> validate_required([:city, :street, :house])
  end
end
