defmodule Delivest.Events.Event do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}

  schema "domain_events" do
    field :type, :string
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :branch_id, Ecto.UUID
    field :payload, :map, default: %{}
    field :actor, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def from?(%__MODULE__{actor: actor}, kind, provider),
    do: actor["kind"] == to_string(kind) and actor["provider"] == to_string(provider)
end
