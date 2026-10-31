defmodule Delivest.Integrations.Inbox.Message do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}

  schema "integration_inbox" do
    field :provider, :string
    field :event_id, :string
    field :branch_id, Ecto.UUID
    field :payload, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :processed, :failed], default: :pending
    field :error, :string
    field :processed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
