defmodule Delivest.Identity.Role do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.{Definitions, Staff}

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :inserted_at],
    default_limit: 10,
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    }
  }

  schema "roles" do
    field :name, :string
    field :permissions, {:array, :string}, default: []

    has_many :staff, Staff

    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :permissions])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_permissions()
    |> unique_constraint(:name, name: :roles__name__uk)
  end

  defp validate_permissions(changeset) do
    validate_subset(changeset, :permissions, Definitions.permissions())
  end
end
