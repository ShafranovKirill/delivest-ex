defmodule Delivest.Oms.Cart do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.CartItem

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "carts" do
    field :session_id, :string
    field :staff_id, :binary_id
    field :branch_id, :binary_id
    field :expires_at, :utc_datetime
    field :promo_code, :string
    field :fulfillment_type, :string
    field :client_id, :binary_id

    has_many :items, CartItem, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @fulfillment_types ~w(delivery pickup dine_in)

  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:session_id, :staff_id, :branch_id, :expires_at])
  end

  def context_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:promo_code, :fulfillment_type, :client_id])
    |> validate_length(:promo_code, max: 32)
    |> validate_inclusion(:fulfillment_type, @fulfillment_types)
  end
end
