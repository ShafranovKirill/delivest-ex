defmodule Delivest.Push.KeyPair do
  use Ecto.Schema

  schema "push_keys" do
    field :public_key, :string
    field :private_key, :string

    timestamps(type: :utc_datetime)
  end
end
