defmodule Delivest.Oms.Order.Address do
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
    |> validate_length(:city, max: 100)
    |> validate_length(:street, max: 150)
    |> validate_length(:house, max: 20)
    |> validate_length(:apartment, max: 20)
    |> validate_length(:floor, max: 2)
    |> validate_length(:entrance, max: 2)
    |> validate_length(:intercom, max: 50)
  end
end
