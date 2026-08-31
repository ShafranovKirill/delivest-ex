defmodule Delivest.Media.File do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "media_files" do
    field :bucket, :string
    field :key, :string
    field :original_name, :string
    field :mime_type, :string
    field :size, :integer

    field :context, Ecto.Enum, values: [:"public/product"]

    field :owner_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:bucket, :key, :original_name, :mime_type, :size, :context, :owner_id])
    |> validate_required([:bucket, :key, :original_name, :mime_type, :size, :context, :owner_id])
    |> validate_number(:size, greater_than: 0)
    |> unique_constraint([:bucket, :key])
  end
end
