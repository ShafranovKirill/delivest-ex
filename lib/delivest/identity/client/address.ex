defmodule Delivest.Identity.Client.Address do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Geo.NormalizedAddress

  @type t :: %__MODULE__{}

  @fields [
            :city,
            :street,
            :house,
            :apartment,
            :floor,
            :entrance,
            :intercom,
            :comment,
            :latitude,
            :longitude,
            :label
          ] ++ NormalizedAddress.fields()

  @identity_fields [:city, :street, :house, :apartment]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "client_addresses" do
    belongs_to :client, Delivest.Identity.Client
    field :city, :string
    field :street, :string
    field :house, :string
    field :apartment, :string
    field :floor, :string
    field :entrance, :string
    field :intercom, :string
    field :comment, :string
    field :latitude, :float
    field :longitude, :float
    field :label, :string
    field :formatted, :string
    field :fias_id, :string
    field :postal_code, :string
    field :district, :string
    field :geo_precision, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, @fields)
    |> validate_required([:street])
    |> validate_length(:city, max: 100)
    |> validate_length(:street, max: 150)
    |> validate_length(:house, max: 20)
    |> validate_length(:apartment, max: 20)
    |> validate_length(:floor, max: 2)
    |> validate_length(:entrance, max: 2)
    |> validate_length(:intercom, max: 50)
    |> validate_length(:comment, max: 255)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_length(:label, max: 30)
    |> NormalizedAddress.validate()
  end

  def fields, do: @fields

  def identity_fields, do: @identity_fields
end
