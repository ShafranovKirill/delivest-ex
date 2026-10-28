defmodule Delivest.Identity.Branch.CourierSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @sources [:staff, :yandex]
  @searches [:manual, :preparing, :ready]

  @primary_key false

  embedded_schema do
    field :source, Ecto.Enum, values: @sources, default: :staff
    field :search, Ecto.Enum, values: @searches, default: :preparing
  end

  def sources, do: @sources
  def searches, do: @searches

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:source, :search])
    |> validate_required([:source, :search])
  end
end
