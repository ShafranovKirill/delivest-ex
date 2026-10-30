defmodule Delivest.Loyalty.Entry do
  use Ecto.Schema

  @kinds [:accrual, :accrual_reversal, :expire, :adjust, :redeem, :refund]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "loyalty_entries" do
    field :client_id, :binary_id
    field :branch_id, :binary_id
    field :order_id, :binary_id
    field :staff_id, :binary_id
    field :kind, Ecto.Enum, values: @kinds
    field :amount, :integer
    field :remaining, :integer, default: 0
    field :expires_at, :utc_datetime
    field :reason, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def kinds, do: @kinds
end
