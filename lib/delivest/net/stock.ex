defmodule Delivest.Net.Stock do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stocks" do
    field :text, :string
    field :is_active, :boolean, default: true

    belongs_to :media, Delivest.Media.File, foreign_key: :media_id, type: :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stock, attrs) do
    stock
    |> cast(attrs, [:media_id, :text, :is_active])
    |> validate_required([:media_id])
  end
end
