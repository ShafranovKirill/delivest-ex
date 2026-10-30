defmodule Delivest.Identity.Branch.IntakeSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :load_minutes, :integer, default: 0
    field :load_until, :utc_datetime
    field :paused_until, :utc_datetime
    field :pause_reason, :string
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:load_minutes, :load_until, :paused_until, :pause_reason])
    |> validate_number(:load_minutes, greater_than_or_equal_to: 0, less_than_or_equal_to: 240)
    |> validate_length(:pause_reason, max: 200)
  end
end
