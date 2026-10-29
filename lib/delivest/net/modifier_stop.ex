defmodule Delivest.Net.ModifierStop do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "modifier_stops" do
    belongs_to :modifier, Delivest.Net.Modifier
    field :branch_id, :binary_id
    field :until, :utc_datetime
    field :staff_id, :binary_id

    timestamps(type: :utc_datetime)
  end
end
