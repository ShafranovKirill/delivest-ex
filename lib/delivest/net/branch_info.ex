defmodule Delivest.Net.BranchInfo do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "branch_info" do
    field :address, :string
    field :phone_number, :string

    belongs_to :branch, Delivest.Net.Branch

    timestamps()
  end

  def changeset(branch_info, attrs) do
    branch_info
    |> cast(attrs, [:address, :phone_number, :branch_id])
  end
end
