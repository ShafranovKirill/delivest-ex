defmodule Delivest.Push.ClientSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Push.Subscription

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "client_push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :locale, :string, default: "ru"

    belongs_to :client, Delivest.Identity.Client

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:endpoint, :p256dh, :auth, :locale])
    |> Subscription.validate_keys()
    |> validate_inclusion(:locale, ~w(ru en))
  end
end
