defmodule Delivest.Net.ModifierGroup do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "modifier_groups" do
    field :name, :string
    field :min, :integer, default: 0
    field :max, :integer, default: 1
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true
    field :is_size, :boolean, default: false

    has_many :modifiers, Delivest.Net.Modifier,
      foreign_key: :group_id,
      preload_order: [asc: :position, asc: :name]

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :min, :max, :position, :is_active, :is_size])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :min, :max])
    |> validate_length(:name, max: 100)
    |> validate_number(:min, greater_than_or_equal_to: 0, less_than_or_equal_to: 50)
    |> validate_number(:max, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_range()
  end

  defp validate_range(changeset) do
    if get_field(changeset, :min) > get_field(changeset, :max),
      do: add_error(changeset, :min, "must not exceed the maximum"),
      else: changeset
  end
end
