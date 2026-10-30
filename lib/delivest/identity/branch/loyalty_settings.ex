defmodule Delivest.Identity.Branch.LoyaltySettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :enabled, :boolean, default: false
    field :per_rubles, :integer, default: 100
    field :stars, :integer, default: 5
    field :expire_days, :integer, default: 180
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :per_rubles, :stars, :expire_days])
    |> validate_required([:per_rubles, :stars, :expire_days])
    |> validate_number(:per_rubles, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:stars, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:expire_days, greater_than: 0, less_than_or_equal_to: 3650)
  end
end
