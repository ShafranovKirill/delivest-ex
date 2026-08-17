defmodule Delivest.Net.Branch do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.{Staff, StaffBranch}

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

  schema "branches" do
    field :name, :string

    many_to_many :staff, Staff, join_through: StaffBranch

    has_one :info, Delivest.Net.BranchInfo, foreign_key: :branch_id

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 50)
    |> unique_constraint(:name, name: :branches__name__uk)
  end
end
