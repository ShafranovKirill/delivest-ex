defmodule Delivest.Oms.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Order.Address
  alias Delivest.Oms.Order.AppliedPromotion
  alias Delivest.Oms.Order.CrmSync
  alias Delivest.Oms.{OrderItem, OrderTransition}

  @type t :: %__MODULE__{}
  @type status ::
          :created | :accepted | :preparing | :ready | :delivering | :completed | :cancelled

  @fulfillment_types [:dine_in, :delivery, :pickup]
  @statuses [:created, :accepted, :preparing, :ready, :delivering, :completed, :cancelled]
  @payment_methods [:cash, :card_offline]
  @channel_payment_methods [:online]
  @cancel_reasons [
    :customer_refused,
    :out_of_stock,
    :unreachable,
    :other,
    :not_confirmed,
    :not_paid,
    :client
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:status, :fulfillment_type, :payment_method, :inserted_at, :number],
    sortable: [:inserted_at, :id, :number, :status, :total_amount],
    default_order: %{
      order_by: [:inserted_at, :id],
      order_directions: [:desc, :desc]
    }
  }

  schema "orders" do
    field :number, :string
    field :daily_number, :integer
    field :business_date, :date
    field :staff_id, :binary_id
    belongs_to :client, Delivest.Identity.Client
    belongs_to :cart, Delivest.Oms.Cart
    field :branch_id, :binary_id
    field :session_id, :string

    field :customer_phone, :string
    field :customer_phone_ext, :string
    field :customer_name, :string
    field :customer_email, :string
    field :persons, :integer

    field :status, Ecto.Enum, values: @statuses, default: :created
    field :fulfillment_type, Ecto.Enum, values: @fulfillment_types, default: :dine_in

    field :payment_method, Ecto.Enum,
      values: @payment_methods ++ @channel_payment_methods,
      default: :cash

    embeds_one :crm, CrmSync, on_replace: :update
    field :source, :string, default: "app"
    embeds_one :channel, Delivest.Oms.Order.ChannelSync, on_replace: :update

    field :total_amount, :integer, default: 0
    field :subtotal_amount, :integer
    field :discount_amount, :integer, default: 0
    field :delivery_amount, :integer, default: 0
    embeds_many :promotions, AppliedPromotion, on_replace: :delete
    field :cook_by, :utc_datetime
    field :comment, :string
    field :cancel_reason, Ecto.Enum, values: @cancel_reasons
    field :cancel_note, :string
    field :cancel_acknowledged_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :awaiting_payment, :boolean, default: false

    embeds_one :address, Address, on_replace: :update
    has_many :items, OrderItem, on_delete: :delete_all, on_replace: :delete
    has_many :transitions, OrderTransition, preload_order: [asc: :id]
    has_many :deliveries, Delivest.Couriers.Delivery, preload_order: [asc: :inserted_at]
    has_many :receipts, Delivest.Fiscal.Receipt, preload_order: [asc: :inserted_at]
    has_many :payments, Delivest.Payments.Payment, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :number,
      :daily_number,
      :business_date,
      :staff_id,
      :client_id,
      :branch_id,
      :cart_id,
      :session_id,
      :customer_phone,
      :customer_phone_ext,
      :customer_name,
      :customer_email,
      :persons,
      :fulfillment_type,
      :payment_method,
      :total_amount,
      :subtotal_amount,
      :discount_amount,
      :delivery_amount,
      :cook_by,
      :comment,
      :deleted_at
    ])
    |> cast_embed(:address, required: false)
    |> cast_assoc(:items)
    |> validate_required([
      :branch_id,
      :fulfillment_type,
      :payment_method,
      :cart_id
    ])
    |> validate_customer()
    |> validate_number(:persons, greater_than_or_equal_to: 0, less_than: 100)
    |> validate_length(:comment, max: 500)
    |> validate_inclusion(:fulfillment_type, @fulfillment_types)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> validate_number(:discount_amount, greater_than_or_equal_to: 0)
    |> validate_cook_by_range()
    |> validate_address_if_delivery()
    |> validate_fulfillment_for_status()
  end

  def statuses, do: @statuses

  def short_number(%__MODULE__{daily_number: number}) when is_integer(number),
    do: Integer.to_string(number)

  def short_number(%__MODULE__{number: number}), do: number

  def crm_managed?(%__MODULE__{crm: crm}), do: not is_nil(crm)

  def courier_leg?(%__MODULE__{fulfillment_type: :delivery}), do: true
  def courier_leg?(%__MODULE__{channel: %{delivery: "yandex"}}), do: true
  def courier_leg?(%__MODULE__{}), do: false

  def source_changeset(changeset, source) do
    changeset
    |> put_change(:source, to_string(source))
    |> validate_change(:source, fn :source, value ->
      if Delivest.Oms.OrderSource.valid?(value), do: [], else: [source: "is invalid"]
    end)
  end

  def customer_changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:customer_name, :customer_phone, :customer_phone_ext, :persons])
    |> validate_customer()
  end

  def channel_changeset(order, attrs) do
    order
    |> cast(%{channel: attrs}, [])
    |> cast_embed(:channel, required: true)
    |> unique_constraint(:channel, name: :orders_channel_external_id_index)
  end

  def paid_online_changeset(changeset), do: put_change(changeset, :payment_method, :online)

  def awaiting_payment_changeset(changeset),
    do: change(changeset, payment_method: :online, awaiting_payment: true)

  def awaiting_payment?(%__MODULE__{awaiting_payment: awaiting}), do: awaiting == true

  def crm_changeset(order, attrs) do
    order
    |> cast(%{crm: attrs}, [])
    |> cast_embed(:crm, required: true)
  end

  def cancel_reasons, do: @cancel_reasons

  def payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:payment_method])
    |> validate_required([:payment_method])
    |> validate_inclusion(:payment_method, @payment_methods)
  end

  def status_changeset(order_or_changeset, status, attrs \\ %{}) do
    order_or_changeset
    |> cast(attrs, [:cancel_reason, :cancel_note])
    |> put_change(:status, status)
    |> settle_cancellation()
  end

  def acknowledge_cancel_changeset(order),
    do: change(order, cancel_acknowledged_at: DateTime.utc_now(:second))

  defp settle_cancellation(changeset) do
    case get_field(changeset, :status) do
      :cancelled ->
        changeset
        |> validate_required([:cancel_reason])
        |> validate_length(:cancel_note, max: 300)

      _status ->
        change(changeset, cancel_reason: nil, cancel_note: nil, cancel_acknowledged_at: nil)
    end
  end

  defp validate_fulfillment_for_status(changeset) do
    if get_field(changeset, :status) == :delivering and changed?(changeset, :fulfillment_type) and
         not courier_leg?(apply_changes(changeset)),
       do: add_error(changeset, :fulfillment_type, "cannot change while the order is on the way"),
       else: changeset
  end

  defp validate_address_if_delivery(changeset) do
    fulfillment_type = get_field(changeset, :fulfillment_type)

    if to_string(fulfillment_type) == "delivery" do
      changeset
      |> validate_required([:address])
    else
      changeset
    end
  end

  defp validate_customer(changeset) do
    changeset
    |> validate_length(:customer_name, max: 100)
    |> validate_length(:customer_email, max: 160)
    |> validate_format(:customer_phone, ~r/^\+\d{7,15}$/, message: "must be in E.164 format")
    |> validate_format(:customer_phone_ext, ~r/^\d{1,10}$/)
    |> validate_format(:customer_email, ~r/^[^\s@]+@[^\s@]+$/)
  end

  defp validate_cook_by_range(changeset) do
    case get_field(changeset, :cook_by) do
      %DateTime{} = cook_by ->
        max_date = Date.add(Date.utc_today(), 30)

        if Date.compare(DateTime.to_date(cook_by), max_date) == :gt do
          add_error(changeset, :cook_by, "must be no more than 30 days from today")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
