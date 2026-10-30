defmodule Delivest.Net.Modifier do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "modifiers" do
    belongs_to :group, Delivest.Net.ModifierGroup
    field :name, :string
    field :price, Delivest.Money.Type, default: 0
    field :max_quantity, :integer, default: 1
    field :is_default, :boolean, default: false
    field :weight, :integer
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true
    field :photo_key, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(modifier, attrs) do
    modifier
    |> cast(attrs, [
      :group_id,
      :name,
      :price,
      :max_quantity,
      :is_default,
      :weight,
      :position,
      :is_active
    ])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:group_id, :name, :price, :max_quantity])
    |> validate_length(:name, max: 100)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:max_quantity, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_number(:weight, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:group_id)
  end
end
