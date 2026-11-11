defmodule Delivest.Notifications.MarketingPushReservation do
  @moduledoc "One durable first-attempt reservation per marketing Push intent."
  use Ecto.Schema

  @primary_key {:intent_id, :binary_id, autogenerate: false}

  schema "marketing_push_reservations" do
    field :client_id, Ecto.UUID
    field :reserved_at, :utc_datetime_usec
  end
end
