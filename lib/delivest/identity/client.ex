defmodule Delivest.Identity.Client do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @statuses [:guest, :active, :blocked]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:phone, :name, :status, :inserted_at, :search_term],
    sortable: [:phone, :name, :status, :inserted_at],
    compound_fields: [search_term: [:name, :phone]],
    default_order: %{
      order_by: [:inserted_at, :status],
      order_directions: [:desc]
    }
  }

  schema "clients" do
    field :phone, :string
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :guest
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:phone, :name, :status, :deleted_at])
    |> validate_required([:phone, :status])
    |> validate_format(:phone, Identity.phone_regex(),
      message:
        dgettext_noop(
          "errors",
          "The number must be in the format +7XXXXXXXXXX"
        )
    )
    |> unique_constraint(:phone, name: :clients__phone__uk)
  end

  def statuses, do: @statuses
end
