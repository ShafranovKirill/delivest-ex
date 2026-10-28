defmodule Delivest.Push.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @key_format ~r/^[A-Za-z0-9_-]+$/
  @hosts ~w(fcm.googleapis.com push.services.mozilla.com notify.windows.com push.apple.com)

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
    |> validate_change(:endpoint, &validate_push_service/2)
    |> validate_format(:p256dh, @key_format)
    |> validate_length(:p256dh, is: 87)
    |> validate_format(:auth, @key_format)
    |> validate_length(:auth, is: 22)
    |> validate_inclusion(:locale, ~w(ru en))
  end

  defp validate_push_service(field, endpoint) do
    host = URI.parse(endpoint).host || ""

    if Enum.any?(hosts(), &(host == &1 or String.ends_with?(host, "." <> &1))),
      do: [],
      else: [{field, "is not a known push service"}]
  end

  defp hosts, do: :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:hosts, @hosts)

  def notified_changeset(subscription, status),
    do: change(subscription, notified_status: to_string(status))
end
