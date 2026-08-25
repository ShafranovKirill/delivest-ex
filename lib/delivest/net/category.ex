defmodule Delivest.Net.Category do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Net.Product

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "categories" do
    field :name, :string
    field :order, :float
    field :is_active, :boolean

    has_many :products, Product

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :order, :is_active])
    |> validate_required([:name])
  end
end
