defmodule Delivest.Push.StaffSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Push.Subscription

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "staff_push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string

    belongs_to :staff, Delivest.Identity.Staff

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:endpoint, :p256dh, :auth])
    |> Subscription.validate_keys()
  end
end
