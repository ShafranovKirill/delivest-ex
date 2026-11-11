defmodule Delivest.Funnel.OrderReceipt do
  @moduledoc "Immutable, explicitly unverified funnel context fixed with an order."
  use Ecto.Schema
  @primary_key {:order_id, :binary_id, autogenerate: false}
  schema "funnel_order_receipts" do
    field :session_id, :binary_id
    field :owner_kind, :string
    field :session_started_at, :utc_datetime_usec
    field :session_last_at, :utc_datetime_usec
    field :source_type, :string
    field :utm_source, :string
    field :utm_medium, :string
    field :utm_campaign, :string
    field :as_of_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
