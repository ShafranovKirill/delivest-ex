defmodule Delivest.Identity.StaffBranch do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}
  @primary_key false
  @foreign_key_type :binary_id

  schema "staff_branches" do
    belongs_to :staff, Delivest.Identity.Staff, primary_key: true
    belongs_to :branch, Delivest.Identity.Branch, primary_key: true

    timestamps()
  end

  def changeset(staff_branch, attrs) do
    staff_branch
    |> cast(attrs, [:staff_id, :branch_id])
    |> validate_required([:staff_id, :branch_id])
    |> foreign_key_constraint(:staff_id,
      name: :staff_branches__staff_id__fk,
      message:
        dgettext_noop(
          "errors",
          "The staff not exist"
        )
    )
    |> foreign_key_constraint(:branch_id,
      name: :staff_branches__branch_id__fk,
      message:
        dgettext_noop(
          "errors",
          "The branch not exist"
        )
    )
    |> unique_constraint([:staff_id, :branch_id],
      name: :staff_branches__staff_id_branch_id__uk,
      message:
        dgettext_noop(
          "errors",
          "The staff alredy has access to this branch"
        )
    )
  end
end
