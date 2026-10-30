defmodule Delivest.Oms.OrderTransition do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order

  @type t :: %__MODULE__{}

  @statuses Order.statuses()
  @sources [:staff, :crm, :channel, :courier, :delivery, :system, :client]

  @foreign_key_type :binary_id

  schema "order_transitions" do
    belongs_to :order, Order
    field :from, Ecto.Enum, values: @statuses
    field :to, Ecto.Enum, values: @statuses
    field :source, Ecto.Enum, values: @sources
    belongs_to :staff, Staff
    field :reason, :string
    field :reverted_at, :utc_datetime_usec
    belongs_to :reverted_by, Staff
    field :revert_reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def sources, do: @sources

  def row(%Order{id: order_id}, {from, to}, source, staff_id, reason, at) do
    %{
      order_id: order_id,
      from: from,
      to: to,
      source: source,
      staff_id: staff_id,
      reason: reason && String.slice(reason, 0, 300),
      inserted_at: at
    }
  end

  def revert_changeset(%__MODULE__{} = transition, staff_id, reason) do
    transition
    |> change(reverted_at: DateTime.utc_now(), reverted_by_id: staff_id)
    |> cast(%{revert_reason: reason}, [:revert_reason])
    |> update_change(:revert_reason, &String.trim/1)
    |> validate_required([:revert_reason])
    |> validate_length(:revert_reason, max: 300)
  end
end
