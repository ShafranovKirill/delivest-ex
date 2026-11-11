defmodule Delivest.Maintenance.DailyRun do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "daily_runs" do
    field :task_key, :string
    field :scope_type, :string
    field :scope_id, :string
    field :local_date, :date
    field :job_id, :integer
    field :status, :string, default: "scheduled"
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end
end
