defmodule Delivest.Couriers.Settlement do
  use Ecto.Schema

  alias Delivest.Identity.Staff

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "courier_settlements" do
    field :branch_id, :binary_id
    belongs_to :courier, Staff
    belongs_to :accepted_by, Staff
    field :cash_amount, :integer
    field :card_amount, :integer
    field :orders_count, :integer
    field :until, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
