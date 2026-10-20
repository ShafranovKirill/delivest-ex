defmodule Delivest.Promo.PromoCode do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Identity.Client
  alias Delivest.Promo.Promotion

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promo_codes" do
    field :branch_id, :binary_id
    field :code, :string
    field :usage_limit, :integer
    field :issued_by_id, :binary_id

    belongs_to :promotion, Promotion
    belongs_to :client, Client

    timestamps(type: :utc_datetime)
  end

  def changeset(promo_code, attrs) do
    promo_code
    |> cast(attrs, [:code, :usage_limit])
    |> update_change(:code, &normalize/1)
    |> validate_required([:code, :branch_id, :promotion_id])
    |> validate_number(:usage_limit, greater_than: 0)
    |> unique_constraint(:code,
      name: :promo_codes_branch_id_code_index,
      message: gettext("this code is already used in the branch")
    )
  end

  def normalize(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  def normalize(code), do: code

  def personal?(%__MODULE__{client_id: client_id}), do: not is_nil(client_id)
end
