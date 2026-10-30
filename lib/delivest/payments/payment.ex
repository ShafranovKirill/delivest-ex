defmodule Delivest.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order

  @type t :: %__MODULE__{}

  @methods [:cash, :card, :online, :sbp, :certificate, :aggregator]
  @statuses [:pending, :authorized, :paid, :failed, :cancelled]
  @fiscalizers [:us, :yookassa, :crm, :aggregator, :yandex_delivery, :none]
  @moves %{
    pending: [:authorized, :paid, :failed, :cancelled],
    authorized: [:paid, :cancelled, :failed],
    paid: [:pending]
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "order_payments" do
    belongs_to :order, Order
    field :branch_id, :binary_id
    field :method, Ecto.Enum, values: @methods
    field :amount, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :provider, :string
    field :external_id, :string
    belongs_to :collected_by, Staff
    field :cash_given, :integer
    field :paid_at, :utc_datetime
    field :fiscalized_by, Ecto.Enum, values: @fiscalizers
    field :details, :map, default: %{}
    belongs_to :settlement, Delivest.Couriers.Settlement

    has_many :refunds, Delivest.Payments.Refund

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :order_id,
      :branch_id,
      :method,
      :amount,
      :status,
      :provider,
      :external_id,
      :collected_by_id,
      :cash_given,
      :paid_at,
      :fiscalized_by,
      :details
    ])
    |> validate_required([:order_id, :branch_id, :method, :amount, :status])
    |> validate_number(:amount, greater_than: 0)
    |> validate_cash_given()
    |> unique_constraint([:provider, :external_id])
  end

  def amount_changeset(%__MODULE__{status: :pending} = payment, attrs) do
    payment
    |> cast(attrs, [:amount, :method, :cash_given])
    |> validate_number(:amount, greater_than: 0)
    |> validate_cash_given()
  end

  def move_changeset(%__MODULE__{status: from} = payment, to, attrs \\ %{}) do
    payment
    |> cast(attrs, [:collected_by_id, :paid_at, :cash_given, :details, :external_id])
    |> put_change(:status, to)
    |> validate_change(:status, fn :status, to ->
      if to in Map.get(@moves, from, []), do: [], else: [status: "cannot move from #{from}"]
    end)
    |> validate_cash_given()
  end

  defp validate_cash_given(changeset) do
    case {get_field(changeset, :method), get_field(changeset, :cash_given)} do
      {_method, nil} ->
        changeset

      {:cash, given} ->
        if given >= get_field(changeset, :amount),
          do: changeset,
          else: add_error(changeset, :cash_given, "is less than the amount")

      _other ->
        add_error(changeset, :cash_given, "is only for cash")
    end
  end
end
