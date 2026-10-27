defmodule Delivest.Integrations.YandexEda.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @accept_modes [:auto, :manual]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :enabled, :boolean, default: false
    field :accept_mode, Ecto.Enum, values: @accept_modes, default: :auto
    field :accept_minutes, :integer, default: 10
    field :markup_percent, :integer, default: 0
    field :round_to, :integer, default: 1
  end

  def accept_modes, do: @accept_modes

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :accept_mode, :accept_minutes, :markup_percent, :round_to])
    |> validate_number(:accept_minutes, greater_than: 0, less_than_or_equal_to: 30)
    |> validate_number(:markup_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:round_to, [1, 5, 10])
  end
end
