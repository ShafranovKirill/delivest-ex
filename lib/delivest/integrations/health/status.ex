defmodule Delivest.Integrations.Health.Status do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}

  schema "integration_health" do
    field :provider, :string
    field :branch_id, Ecto.UUID
    field :status, Ecto.Enum, values: [:ok, :failed, :auth, :warning]
    field :message, :string
    field :checked_at, :utc_datetime_usec
  end
end
