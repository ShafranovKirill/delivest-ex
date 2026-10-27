defmodule Delivest.Delivery.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Delivery.Threshold

  @modes [:flat, :zones]

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "delivery_settings" do
    field :mode, Ecto.Enum, values: @modes, default: :flat
    embeds_many :thresholds, Threshold, on_replace: :delete
    belongs_to :branch, Delivest.Identity.Branch

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:mode])
    |> cast_embed(:thresholds, sort_param: :thresholds_sort, drop_param: :thresholds_drop)
    |> validate_required([:mode])
    |> Threshold.validate_list(:thresholds)
    |> unique_constraint(:branch_id)
  end
end
