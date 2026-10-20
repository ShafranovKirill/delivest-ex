defmodule Delivest.Identity.Client.Address do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @fields [:city, :street, :house, :apartment, :floor, :entrance, :intercom]

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
  end

  def fields, do: @fields
end
