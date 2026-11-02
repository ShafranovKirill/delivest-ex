defmodule Delivest.Identity.Branch.LoyaltySettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :shop_enabled, :boolean, default: false
    field :enabled, :boolean, default: false

    # The rate and the expiry are a franchise-wide policy. The fields stay here
    # because Delivest.Loyalty.settings/1 overlays the franchise values on this
    # struct for the rest of the code; they are not edited per branch.
    field :per_rubles, :integer, default: 100
    field :stars, :integer, default: 5
    field :expire_days, :integer, default: 180

    field :spend_enabled, :boolean, default: false
    field :max_percent, :integer, default: 50
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:shop_enabled, :enabled, :spend_enabled, :max_percent])
    |> validate_number(:max_percent, greater_than: 0, less_than_or_equal_to: 100)
  end
end
