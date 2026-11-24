defmodule Delivest.DeliveryMeasurement.ActualEvent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "delivery_actual_events" do
    field :order_id, :binary_id
    field :source, :string
    field :event_id, :string
    field :occurred_at, :utc_datetime
    field :received_at, :utc_datetime
  end
end
