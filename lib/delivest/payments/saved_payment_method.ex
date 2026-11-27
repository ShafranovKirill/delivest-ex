defmodule Delivest.Payments.SavedPaymentMethod do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_payment_methods" do
    belongs_to :client, Delivest.Identity.Client
    field :shop_id, :string
    field :provider_method_id, :string, redact: true
    field :type, :string
    field :title, :string
    field :last4, :string
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime)
  end

  def provider_changeset(method, attrs) do
    method
    |> cast(attrs, [:type, :title, :last4])
    |> validate_length(:type, max: 40)
    |> validate_length(:title, max: 100)
    |> validate_format(:last4, ~r/^\d{4}$/)
    |> unique_constraint([:client_id, :shop_id, :provider_method_id],
      name: :saved_payment_methods_owner_shop_provider_index
    )
  end
end
