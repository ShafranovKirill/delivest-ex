defmodule Delivest.Payments.Refund do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.Staff
  alias Delivest.Payments.Payment

  @type t :: %__MODULE__{}

  @statuses [:pending, :succeeded, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "order_refunds" do
    belongs_to :payment, Payment
    field :order_id, :binary_id
    field :amount, :integer
    field :reason, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :provider, :string
    field :external_id, :string
    belongs_to :refunded_by, Staff
    field :refunded_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, [
      :payment_id,
      :order_id,
      :amount,
      :reason,
      :status,
      :provider,
      :external_id,
      :refunded_by_id,
      :refunded_at
    ])
    |> validate_required([:payment_id, :order_id, :amount, :status])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:reason, max: 300)
    |> unique_constraint([:provider, :external_id])
  end

  def move_changeset(%__MODULE__{status: :pending} = refund, to, attrs \\ %{})
      when to in [:succeeded, :failed] do
    refund
    |> cast(attrs, [:external_id, :refunded_at])
    |> put_change(:status, to)
  end
end
