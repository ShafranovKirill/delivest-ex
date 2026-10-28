defmodule Delivest.Identity.Branch.KitchenSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :enabled, :boolean, default: false
    field :lead_minutes, :integer, default: 90
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :lead_minutes])
    |> validate_required([:lead_minutes])
    |> validate_number(:lead_minutes, greater_than_or_equal_to: 0, less_than_or_equal_to: 1440)
  end
end
