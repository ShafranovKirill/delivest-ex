defmodule Delivest.Events.Delivery do
  use Ecto.Schema

  @primary_key false
  schema "event_deliveries" do
    belongs_to :event, Delivest.Events.Event, type: Ecto.UUID, primary_key: true
    field :subscriber, :string, primary_key: true
    field :status, :string, default: "pending"
    field :delivered_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
