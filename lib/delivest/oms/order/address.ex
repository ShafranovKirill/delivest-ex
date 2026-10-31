defmodule Delivest.Oms.Order.Address do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Geo.{House, NormalizedAddress}

  @primary_key false
  embedded_schema do
    field :city, :string
    field :street, :string
    field :house, :string
    field :block, :string
    field :building, :string
    field :apartment, :string
    field :floor, :string
    field :entrance, :string
    field :intercom, :string
    field :comment, :string
    field :latitude, :float
    field :longitude, :float
    field :formatted, :string
    field :fias_id, :string
    field :postal_code, :string
    field :district, :string
    field :geo_precision, :integer
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :city,
      :street,
      :house,
      :block,
      :building,
      :apartment,
      :floor,
      :entrance,
      :intercom,
      :comment,
      :latitude,
      :longitude
      | NormalizedAddress.fields()
    ])
    |> validate_length(:city, max: 100)
    |> validate_length(:street, max: 150)
    |> split_house()
    |> validate_length(:house, max: 20)
    |> validate_length(:block, max: 10)
    |> validate_length(:building, max: 10)
    |> validate_length(:apartment, max: 20)
    |> validate_length(:floor, max: 2)
    |> validate_length(:entrance, max: 2)
    |> validate_length(:intercom, max: 50)
    |> validate_length(:comment, max: 255)
    |> NormalizedAddress.validate()
  end

  def house_line(address), do: House.line(address)

  defp split_house(changeset) do
    params = changeset.params || %{}

    if changed?(changeset, :house) and not Map.has_key?(params, "block") and
         not Map.has_key?(params, "building") do
      changeset |> get_field(:house) |> House.split() |> then(&change(changeset, &1))
    else
      changeset
    end
  end
end
