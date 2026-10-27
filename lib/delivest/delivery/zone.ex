defmodule Delivest.Delivery.Zone do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Delivery.{Geometry, Threshold}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "delivery_zones" do
    field :name, :string
    field :color, :string, default: "#2563eb"
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0
    field :polygon, :map
    field :radius_km, :float
    field :geometry_version, :integer, default: 1
    field :delivery_minutes, :integer
    field :deleted_at, :utc_datetime
    embeds_many :thresholds, Threshold, on_replace: :delete
    belongs_to :branch, Delivest.Identity.Branch

    timestamps(type: :utc_datetime)
  end

  def changeset(zone, attrs) do
    zone
    |> cast(attrs, [:name, :color, :enabled, :position, :delivery_minutes])
    |> cast_embed(:thresholds, sort_param: :thresholds_sort, drop_param: :thresholds_drop)
    |> validate_required([:name, :color])
    |> validate_length(:name, max: 255)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)
    |> validate_number(:delivery_minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> Threshold.validate_list(:thresholds)
  end

  def radius_changeset(zone, center, radius) do
    changeset =
      zone
      |> cast(%{radius_km: radius}, [:radius_km])
      |> validate_required([:radius_km])
      |> validate_number(:radius_km, greater_than: 0, less_than_or_equal_to: 100)

    if changeset.valid?,
      do:
        merge(
          changeset,
          polygon_changeset(zone, Geometry.circle(center, get_field(changeset, :radius_km)))
        ),
      else: changeset
  end

  def polygon_changeset(zone, polygon) do
    case Geometry.normalize(polygon) do
      {:ok, normalized} when normalized == zone.polygon ->
        change(zone)

      {:ok, normalized} when is_nil(zone.polygon) ->
        change(zone, polygon: normalized)

      {:ok, normalized} ->
        change(zone, polygon: normalized, geometry_version: zone.geometry_version + 1)

      {:error, message} ->
        zone |> change() |> add_error(:polygon, message)
    end
  end
end
