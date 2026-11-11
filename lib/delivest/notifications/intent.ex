defmodule Delivest.Notifications.Intent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customer_notification_intents" do
    belongs_to :notification, Delivest.Notifications.Notification
    field :channel, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :job_id, :integer
    field :fanout_cursor, Ecto.UUID
    field :fanout_complete, :boolean, default: false
    field :due_at, :utc_datetime_usec
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(intent, attrs) do
    intent
    |> cast(attrs, [
      :channel,
      :status,
      :attempts,
      :job_id,
      :fanout_cursor,
      :fanout_complete,
      :due_at,
      :last_error
    ])
    |> validate_required([:channel, :status, :due_at])
    |> validate_inclusion(:channel, ~w(in_app push sms))
    |> validate_inclusion(
      :status,
      ~w(pending queued inflight sent delivered unknown failed skipped canceled)
    )
    |> unique_constraint([:notification_id, :channel])
  end
end
