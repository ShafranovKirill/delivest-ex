defmodule Delivest.Integrations.Crm.FrontpadStopRefresh.State do
  use Ecto.Schema

  @primary_key {:branch_id, Ecto.UUID, autogenerate: false}

  schema "frontpad_stop_refresh_states" do
    field :job_id, :integer
    field :status, :string, default: "queued"
    field :last_attempt_at, :utc_datetime_usec
    field :last_success_at, :utc_datetime_usec
    field :last_good_count, :integer
    field :last_good_unlinked, {:array, :string}, default: []
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end
end
