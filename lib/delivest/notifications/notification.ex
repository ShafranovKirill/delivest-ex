defmodule Delivest.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customer_notifications" do
    belongs_to :client, Delivest.Identity.Client
    belongs_to :branch, Delivest.Identity.Branch
    field :idempotency_key, :string
    field :source_type, :string
    field :source_id, Ecto.UUID
    field :source_feature, :string
    field :source_scope_key, :string
    field :source_generation_franchise, :integer
    field :source_generation_branch, :integer
    field :notification_generation_franchise, :integer
    field :notification_generation_branch, :integer
    field :title, :string
    field :body, :string
    field :cta, :map
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :idempotency_key,
      :source_type,
      :source_id,
      :source_feature,
      :source_scope_key,
      :source_generation_franchise,
      :source_generation_branch,
      :notification_generation_franchise,
      :notification_generation_branch,
      :title,
      :body,
      :cta,
      :expires_at
    ])
    |> validate_required([
      :idempotency_key,
      :source_type,
      :source_id,
      :source_feature,
      :source_scope_key,
      :source_generation_franchise,
      :source_generation_branch,
      :notification_generation_franchise,
      :notification_generation_branch,
      :title,
      :body
    ])
    |> validate_length(:title, max: 140)
    |> validate_length(:body, max: 1000)
    |> unique_constraint(:idempotency_key)
  end
end
