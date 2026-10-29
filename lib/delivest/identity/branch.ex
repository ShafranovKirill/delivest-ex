defmodule Delivest.Identity.Branch do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity.{Staff, StaffBranch}

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @derive {Phoenix.Param, key: :slug}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "branches" do
    field :name, :string
    field :slug, :string
    field :code, :string
    field :is_active, :boolean

    many_to_many :staff, Staff, join_through: StaffBranch

    has_one :info, Delivest.Identity.Branch.BranchInfo, foreign_key: :branch_id

    many_to_many :stocks, Delivest.Net.Stock,
      join_through: Delivest.Relations.EntityRelation,
      join_keys: [from_id: :id, to_id: :id],
      join_where: [from_entity_type: "Branch", to_entity_type: "Stock"]

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :slug, :code, :is_active])
    |> update_change(:code, &String.upcase(String.trim(&1)))
    |> validate_required([:name, :code])
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:slug, min: 2, max: 20)
    |> unique_constraint(:name, name: :branches__name__uk)
    |> unique_constraint(:slug, name: :branches__slug_uk)
    |> unique_constraint(:code, name: :branches_code_uk)
    |> validate_format(:code, ~r/^[A-Z0-9]{2,6}$/,
      message: dgettext_noop("errors", "must be 2 to 6 latin letters or digits")
    )
    |> validate_format(:slug, slug_regex(),
      message:
        dgettext_noop(
          "errors",
          "can only contain lowercase letters, numbers, and hyphens"
        )
    )
  end

  def code_from(text) when is_binary(text) do
    text
    |> Delivest.Slug.slugify()
    |> String.replace("-", "")
    |> String.upcase()
    |> String.slice(0, 6)
  end

  def code_from(_text), do: ""

  defp slug_regex, do: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
end
