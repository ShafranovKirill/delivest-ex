defmodule Delivest.Events.Delivery do
  use Ecto.Schema

  @primary_key false
  schema "event_deliveries" do
    field :event_id, Ecto.UUID, primary_key: true
    field :subscriber, :string, primary_key: true
    field :status, :string, default: "pending"
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end
end
