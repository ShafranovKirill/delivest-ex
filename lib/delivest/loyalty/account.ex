defmodule Delivest.Loyalty.Account do
  use Ecto.Schema

  @primary_key {:client_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "loyalty_accounts" do
    field :balance, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
