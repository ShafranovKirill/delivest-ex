defmodule Delivest.Oms.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Order.Address
  alias Delivest.Oms.OrderItem

  @type t :: %__MODULE__{}

  @fulfillment_types [:dine_in, :delivery, :pickup]
  @statuses [:created, :preparing, :ready, :delivering, :completed, :cancelled]
  @payment_methods [:cash, :card_offline]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "orders" do
    field :number, :string
    field :staff_id, :binary_id
    field :client_id, :binary_id
    field :branch_id, :binary_id

    field :status, Ecto.Enum, values: @statuses, default: :created
    field :fulfillment_type, Ecto.Enum, values: @fulfillment_types, default: :dine_in
    field :payment_method, Ecto.Enum, values: @payment_methods, default: :cash

    field :total_amount, :integer, default: 0
    field :comment, :string
    field :deleted_at, :utc_datetime

    embeds_one :address, Address, on_replace: :update
    has_many :items, OrderItem, on_delete: :delete_all, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :number,
      :staff_id,
      :client_id,
      :branch_id,
      :status,
      :fulfillment_type,
      :payment_method,
      :total_amount,
      :comment,
      :deleted_at
    ])
    |> cast_embed(:address, required: false)
    |> cast_assoc(:items)
    |> validate_required([
      :number,
      :branch_id,
      :status,
      :fulfillment_type,
      :payment_method,
      :total_amount
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:fulfillment_type, @fulfillment_types)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> validate_address_if_delivery()
  end

  defp validate_address_if_delivery(changeset) do
    case get_field(changeset, :fulfillment_type) do
      :delivery -> validate_required(changeset, [:address])
      _ -> changeset
    end
  end
end
