defmodule Delivest.Push.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @key_format ~r/^[A-Za-z0-9_-]+$/

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :locale, :string
    field :notified_status, :string

    belongs_to :order, Delivest.Oms.Order

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:endpoint, :p256dh, :auth, :locale])
    |> validate_required([:endpoint, :p256dh, :auth])
    |> validate_format(:endpoint, ~r{^https://})
    |> validate_length(:endpoint, max: 2000)
    |> validate_format(:p256dh, @key_format)
    |> validate_length(:p256dh, is: 87)
    |> validate_format(:auth, @key_format)
    |> validate_length(:auth, is: 22)
    |> validate_inclusion(:locale, ~w(ru en))
  end

  def notified_changeset(subscription, status),
    do: change(subscription, notified_status: to_string(status))
end
