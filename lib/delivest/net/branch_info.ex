defmodule Delivest.Net.BranchInfo do
  use Ecto.Schema
  import Ecto.Changeset

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
