defmodule Delivest.Loyalty.ExpiryNotification do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "loyalty_expiry_notifications" do
    field :expires_on, :date
    field :branch_id, :binary_id
    field :stars, :integer
    field :expires_at, :utc_datetime

    belongs_to :client, Delivest.Identity.Client

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
