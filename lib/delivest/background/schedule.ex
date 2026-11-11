defmodule Delivest.Background.Schedule do
  use Ecto.Schema

  schema "background_schedules" do
    field :kind, :string
    field :scope_key, :string
    field :next_at, :utc_datetime_usec
    field :last_success_at, :utc_datetime_usec
    field :last_error_at, :utc_datetime_usec
    field :last_error, :string
    field :running, :boolean, default: false
    field :rerun_requested, :boolean, default: false
    field :current_job_id, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
