defmodule Delivest.Oms.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.Order.Address
  alias Delivest.Oms.Order.AppliedPromotion
  alias Delivest.Oms.Order.CrmSync
  alias Delivest.Oms.OrderItem

  @type t :: %__MODULE__{}

  @fulfillment_types [:dine_in, :delivery, :pickup]
  @statuses [:created, :preparing, :ready, :delivering, :completed, :cancelled, :crm]
  @progress_statuses [:created, :preparing, :ready, :delivering, :completed, :cancelled]
  @payment_methods [:cash, :card_offline]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:status, :fulfillment_type, :payment_method, :inserted_at, :number],
    sortable: [:inserted_at, :number, :status, :total_amount],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "orders" do
    field :number, :string
    field :staff_id, :binary_id
    belongs_to :client, Delivest.Identity.Client
    belongs_to :cart, Delivest.Oms.Cart
    field :branch_id, :binary_id
    field :session_id, :string

    field :customer_phone, :string, virtual: true
    field :customer_name, :string, virtual: true

    field :status, Ecto.Enum, values: @statuses, default: :created
    field :fulfillment_type, Ecto.Enum, values: @fulfillment_types, default: :dine_in
    field :payment_method, Ecto.Enum, values: @payment_methods, default: :cash

    embeds_one :crm, CrmSync, on_replace: :update

    field :total_amount, :integer, default: 0
    field :subtotal_amount, :integer
    field :discount_amount, :integer, default: 0
    embeds_many :promotions, AppliedPromotion, on_replace: :delete
    field :cook_by, :naive_datetime
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
      :cart_id,
      :session_id,
      :customer_phone,
      :customer_name,
      :status,
      :fulfillment_type,
      :payment_method,
      :total_amount,
      :subtotal_amount,
      :discount_amount,
      :cook_by,
      :comment,
      :deleted_at
    ])
    |> cast_embed(:address, required: false)
    |> cast_assoc(:items)
    |> validate_required([
      :branch_id,
      :status,
      :fulfillment_type,
      :payment_method,
      :cart_id
    ])
    |> validate_length(:customer_name, max: 100)
    |> validate_length(:comment, max: 500)
    |> validate_phone()
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:fulfillment_type, @fulfillment_types)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> validate_number(:discount_amount, greater_than_or_equal_to: 0)
    |> validate_cook_by_range()
    |> validate_address_if_delivery()
    |> settle_delivering_status()
  end

  def progress_statuses, do: @progress_statuses

  def statuses_for(fulfillment_type) when fulfillment_type in [:delivery, "delivery"],
    do: @progress_statuses

  def statuses_for(_fulfillment_type), do: List.delete(@progress_statuses, :delivering)

  def crm_changeset(order, attrs) do
    order
    |> cast(%{crm: attrs}, [])
    |> cast_embed(:crm, required: true)
  end

  def details_changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :payment_method])
    |> validate_required([:status, :payment_method])
    |> validate_status_for_fulfillment()
  end

  defp settle_delivering_status(changeset) do
    if get_field(changeset, :status) == :delivering and
         get_field(changeset, :fulfillment_type) != :delivery,
       do: put_change(changeset, :status, :ready),
       else: changeset
  end

  defp validate_status_for_fulfillment(changeset) do
    status = get_field(changeset, :status)

    if status in @progress_statuses and
         status not in statuses_for(get_field(changeset, :fulfillment_type)),
       do: add_error(changeset, :status, "is not available for this fulfillment type"),
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

  defp validate_phone(changeset) do
    case get_field(changeset, :customer_phone) do
      nil ->
        changeset

      "" ->
        changeset

      _phone ->
        changeset
        |> validate_format(:customer_phone, ~r/^\+7\d{10}$/,
          message: "must be in format +7XXXXXXXXXX"
        )
    end
  end

  defp validate_cook_by_range(changeset) do
    case get_field(changeset, :cook_by) do
      %NaiveDateTime{} = cook_by ->
        max_date = Date.add(Date.utc_today(), 30)

        if Date.compare(NaiveDateTime.to_date(cook_by), max_date) == :gt do
          add_error(changeset, :cook_by, "must be no more than 30 days from today")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
