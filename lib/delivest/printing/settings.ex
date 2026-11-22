defmodule Delivest.Printing.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :kitchen_enabled, :boolean, default: false
    field :customer_enabled, :boolean, default: false
    embeds_one :kitchen, Delivest.Printing.Preset, on_replace: :update
    embeds_one :customer, Delivest.Printing.Preset, on_replace: :update
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:kitchen_enabled, :customer_enabled])
    |> cast_embed(:kitchen, with: &Delivest.Printing.Preset.kitchen_changeset/2)
    |> cast_embed(:customer, with: &Delivest.Printing.Preset.customer_changeset/2)
  end
end
