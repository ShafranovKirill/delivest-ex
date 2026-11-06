defmodule Delivest.Loyalty.ExpiryDelivery do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "loyalty_expiry_deliveries" do
    belongs_to :notification, Delivest.Loyalty.ExpiryNotification
    field :subscription_id, :binary_id

    field :status, Ecto.Enum,
      values: [:pending, :sending, :delivered, :expired, :rejected, :failed, :unknown],
      default: :pending

    field :attempts, :integer, default: 0
    field :last_error, :string

    timestamps(type: :utc_datetime)
  end
end
