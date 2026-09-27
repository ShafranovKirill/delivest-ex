defmodule Delivest.Oms.Cart do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.CartItem

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "carts" do
    field :session_id, :string
    field :staff_id, :binary_id
    field :branch_id, :binary_id
    field :expires_at, :utc_datetime

    has_many :items, CartItem, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:session_id, :staff_id, :branch_id, :expires_at])
    |> validate_at_least_one_owner()
  end

  defp validate_at_least_one_owner(changeset) do
    case {get_field(changeset, :session_id), get_field(changeset, :staff_id)} do
      {nil, nil} ->
        add_error(
          changeset,
          :session_id,
          dgettext_noop("errors", "must provide either session_id or staff_id")
        )

      _ ->
        changeset
    end
  end
end
