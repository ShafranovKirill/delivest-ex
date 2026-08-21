defmodule Delivest.Net.CategoriesBranches do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}
  @primary_key false
  @foreign_key_type :binary_id

  schema "categories_branches" do
    field :order, :float, default: 0.0

    belongs_to :category, Delivest.Net.Category, primary_key: true
    belongs_to :branch, Delivest.Net.Branch, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(categories_branch, attrs) do
    categories_branch
    |> cast(attrs, [:order, :category_id, :branch_id])
    |> validate_required([:order, :category_id, :branch_id])
    |> foreign_key_constraint(:category_id,
      name: :categories_branches__category_id__fk,
      message:
        dgettext_noop(
          "errors",
          "The category does not exist"
        )
    )
    |> foreign_key_constraint(:branch_id,
      name: :categories_branches__branch_id__fk,
      message:
        dgettext_noop(
          "errors",
          "The branch does not exist"
        )
    )
  end
end
