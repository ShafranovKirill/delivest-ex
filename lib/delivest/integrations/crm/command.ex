defmodule Delivest.Integrations.Crm.Command do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "crm_commands" do
    field :order_id, Ecto.UUID
    field :provider, :string
    field :action, :string
    field :args, :map, default: %{}
    field :event_id, Ecto.UUID
    field :job_id, :integer
    field :status, :string, default: "pending"
    field :claim_token, Ecto.UUID
    field :claim_attempt, :integer
    field :claimed_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :last_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(command, attrs) do
    command
    |> cast(attrs, [
      :order_id,
      :provider,
      :action,
      :args,
      :event_id,
      :job_id,
      :status,
      :claim_token,
      :claim_attempt,
      :claimed_at,
      :resolved_at,
      :last_error
    ])
    |> validate_required([:order_id, :provider, :action, :args])
    |> unique_constraint([:event_id, :action])
    |> unique_constraint(:job_id)
  end
end
