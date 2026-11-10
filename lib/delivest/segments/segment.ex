defmodule Delivest.Segments.Segment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "segments" do
    field :name, :string
    field :kind, Ecto.Enum, values: [:manual, :dynamic]
    field :scope, Ecto.Enum, values: [:franchise, :branches]
    field :rules, :map
    field :revision, :integer, default: 1
    field :published_snapshot_id, :binary_id
    field :last_refreshed_at, :utc_datetime
    field :last_refresh_error, :string
    many_to_many :branches, Delivest.Identity.Branch, join_through: "segment_branches"
    timestamps(type: :utc_datetime)
  end

  def create_changeset(segment, attrs) do
    segment
    |> cast(attrs, [:name, :kind, :scope, :rules])
    |> validate_required([:name, :kind, :scope])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_rules()
  end

  def update_changeset(segment, attrs) do
    segment
    |> cast(attrs, [:name, :rules])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_required([:name])
    |> validate_rules()
    |> optimistic_lock(:revision)
  end

  defp validate_rules(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :rules)} do
      {:manual, nil} ->
        changeset

      {:dynamic, rules} ->
        if match?({:ok, _}, Delivest.Segments.Rules.validate(rules)),
          do: changeset,
          else: add_error(changeset, :rules, "invalid conditions")

      _ ->
        add_error(changeset, :rules, "must be empty for a manual segment")
    end
  end
end
