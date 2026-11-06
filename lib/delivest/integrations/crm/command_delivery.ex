defmodule Delivest.Integrations.Crm.CommandDelivery do
  use Ecto.Schema

  @primary_key {:job_id, :integer, autogenerate: false}
  schema "crm_command_deliveries" do
    field :order_id, Ecto.UUID
    field :branch_id, Ecto.UUID
    field :event_id, Ecto.UUID
    field :args, :map
    field :execution_job_id, :integer
    field :phase, :string, default: "pending"
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end
end
