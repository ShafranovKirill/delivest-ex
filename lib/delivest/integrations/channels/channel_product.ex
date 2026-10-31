defmodule Delivest.Integrations.Channels.ChannelProduct do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_products" do
    field :channel, :string
    field :enabled, :boolean, default: true
    field :price, Delivest.Money.Type
    belongs_to :product, Delivest.Net.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(channel_product, attrs) do
    channel_product
    |> cast(attrs, [:enabled, :price], empty_values: [nil, ""])
    |> validate_number(:price, greater_than: 0, less_than: 100_000_000)
    |> unique_constraint([:channel, :product_id])
  end
end
