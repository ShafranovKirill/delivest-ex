defmodule Delivest.Integrations.Rkeeper.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :object_id, :string
    field :sandbox, :boolean, default: false
    field :sync_stops, :boolean, default: false
    field :delivery_category_code, :string
    field :delivery_type_code, :string
    field :pickup_category_code, :string
    field :pickup_type_code, :string
    field :prepay_currency, :string
    field :void_reason_code, :string
  end

  def changeset(settings, attrs, required? \\ false) do
    settings
    |> cast(attrs, [
      :object_id,
      :sandbox,
      :sync_stops,
      :delivery_category_code,
      :delivery_type_code,
      :pickup_category_code,
      :pickup_type_code,
      :prepay_currency,
      :void_reason_code
    ])
    |> update_change(:object_id, &String.trim/1)
    |> validate_format(:object_id, ~r/^\d+$/)
    |> then(&if(required?, do: validate_required(&1, [:object_id]), else: &1))
  end
end
