defmodule Delivest.DeliveryMeasurement.PromiseHistory do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "delivery_promise_history" do
    field :order_id, :binary_id
    field :staff_id, :binary_id
    field :source, :string
    field :promised_at, :utc_datetime
    field :reason, :string
    field :recorded_at, :utc_datetime_usec
  end
end
