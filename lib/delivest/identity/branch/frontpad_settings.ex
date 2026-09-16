defmodule Delivest.Identity.Branch.FrontpadSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :frontpad_branch_id, :string
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:frontpad_branch_id])
  end
end
