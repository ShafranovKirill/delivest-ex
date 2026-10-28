defmodule Delivest.Couriers.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order

  @type t :: %__MODULE__{}
  @type status :: :searching | :assigned | :picked_up | :delivered | :cancelled | :failed

  @providers [:staff, :yandex]
  @active [:searching, :assigned, :picked_up]
  @statuses @active ++ [:delivered, :cancelled, :failed]
  @close_reasons [
    :refused,
    :unassigned,
    :reassigned,
    :not_found,
    :order_cancelled,
    :order_completed,
    :handed_over
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "deliveries" do
    belongs_to :order, Order
    field :branch_id, :binary_id
    field :provider, Ecto.Enum, values: @providers
    field :status, Ecto.Enum, values: @statuses, default: :searching
    belongs_to :courier, Staff
    belongs_to :assigned_by, Staff
    field :close_reason, Ecto.Enum, values: @close_reasons
    field :external_id, :string
    field :details, :map, default: %{}
    field :assigned_at, :utc_datetime_usec
    field :picked_up_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def active, do: @active

  def active?(%__MODULE__{status: status}), do: status in @active

  def new(%Order{} = order, provider) do
    %__MODULE__{order_id: order.id, branch_id: order.branch_id, provider: provider}
    |> change()
    |> unique_constraint(:order_id, name: :deliveries_active_order_index)
  end

  def assign_changeset(delivery, %Staff{} = courier, assigned_by) do
    delivery
    |> change(
      status: :assigned,
      courier_id: courier.id,
      assigned_by_id: assigned_by && assigned_by.id,
      assigned_at: DateTime.utc_now()
    )
    |> unique_constraint(:order_id, name: :deliveries_active_order_index)
  end

  def pick_up_changeset(delivery),
    do: change(delivery, status: :picked_up, picked_up_at: DateTime.utc_now())

  def close_changeset(delivery, status, reason) when status in [:delivered, :cancelled, :failed],
    do: change(delivery, status: status, close_reason: reason, closed_at: DateTime.utc_now())
end
