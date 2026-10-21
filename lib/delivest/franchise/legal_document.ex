defmodule Delivest.Franchise.LegalDocument do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds [:privacy, :consent, :offer, :terms]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "legal_documents" do
    field :kind, Ecto.Enum, values: @kinds
    field :body, :string

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:kind, :body])
    |> validate_required([:kind, :body])
    |> validate_length(:body, max: 100_000)
    |> unique_constraint(:kind)
  end
end
