defmodule Delivest.Integrations.Frontpad.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :api_key, :string, redact: true
    field :affiliate, :string
  end

  def changeset(settings, attrs, required? \\ false) do
    settings
    |> cast(attrs, [:api_key, :affiliate])
    |> then(&if(required?, do: validate_required(&1, [:api_key]), else: &1))
  end
end
