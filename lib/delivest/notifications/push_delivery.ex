defmodule Delivest.Notifications.PushDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customer_notification_push_deliveries" do
    belongs_to :intent, Delivest.Notifications.Intent
    field :subscription_id, Ecto.UUID
    field :job_id, :integer
    field :status, :string, default: "queued"
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:subscription_id, :job_id, :status, :last_error])
    |> validate_required([:subscription_id, :status])
    |> validate_inclusion(:status, ~w(queued inflight sent unknown skipped canceled))
    |> unique_constraint([:intent_id, :subscription_id])
  end
end
