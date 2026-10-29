defmodule Delivest.Integrations.Journal.Request do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}

  schema "integration_requests" do
    field :provider, :string
    field :branch_id, Ecto.UUID
    field :order_id, Ecto.UUID
    field :direction, Ecto.Enum, values: [:in, :out]
    field :method, :string
    field :url, :string
    field :status, :integer
    field :duration_ms, :integer
    field :request, :string
    field :response, :string
    field :error, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def failed?(%__MODULE__{error: error}) when is_binary(error), do: true
  def failed?(%__MODULE__{status: status}) when is_integer(status), do: status >= 400
  def failed?(_request), do: false
end
