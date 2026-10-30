defmodule Delivest.Fiscal.Receipt do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order

  @type t :: %__MODULE__{}

  @kinds [:sell, :sell_refund, :sell_correction]
  @stages [:full_payment, :full_prepayment]
  @statuses [:pending, :wait, :done, :fail]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fiscal_receipts" do
    belongs_to :order, Order
    field :branch_id, :binary_id
    field :payment_ids, {:array, :binary_id}, default: []
    belongs_to :refund_of, __MODULE__
    belongs_to :issued_by, Staff
    field :kind, Ecto.Enum, values: @kinds
    field :stage, Ecto.Enum, values: @stages, default: :full_payment
    field :provider, :string
    field :uuid, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :amount, :integer
    field :request, :map
    field :payload, :map
    field :error, :string
    field :attempts, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :order_id,
      :branch_id,
      :payment_ids,
      :refund_of_id,
      :issued_by_id,
      :kind,
      :stage,
      :provider,
      :amount,
      :request
    ])
    |> validate_required([:order_id, :branch_id, :kind, :stage, :provider, :amount])
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint([:order_id, :kind, :stage], name: :fiscal_receipts_one_per_order)
  end

  def result_changeset(receipt, attrs),
    do: cast(receipt, attrs, [:uuid, :status, :payload, :error, :attempts])

  def ofd_url(%__MODULE__{payload: %{"ofd_receipt_url" => url}}) when is_binary(url), do: url
  def ofd_url(_receipt), do: nil
end
