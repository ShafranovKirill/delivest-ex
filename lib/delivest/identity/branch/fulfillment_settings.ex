defmodule Delivest.Identity.Branch.FulfillmentSettings do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field :delivery, :boolean, default: true
    field :pickup, :boolean, default: true
    field :dine_in, :boolean, default: true
  end

  def changeset(settings, attrs),
    do:
      settings
      |> cast(attrs, [:delivery, :pickup, :dine_in])
      |> validate_required([:delivery, :pickup, :dine_in])

  def enabled(settings \\ nil) do
    settings = settings || %__MODULE__{}
    Enum.filter([:delivery, :pickup, :dine_in], &(Map.get(settings, &1) == true))
  end
end
