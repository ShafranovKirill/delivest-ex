defmodule Delivest.Oms.Order.CrmSync do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending confirming sent failed unknown)
  @remote_statuses ~w(created accepted preparing ready delivering completed cancelled)

  @primary_key false
  embedded_schema do
    field :provider, :string
    field :external_id, :string
    field :external_number, :string
    field :ref, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :sent_at, :utc_datetime
    field :warnings, :map
    field :alert, :string
    field :remote_status, :string
    field :remote_status_code, :string
    field :remote_status_at, :utc_datetime
  end

  def changeset(sync, attrs) do
    sync
    |> cast(attrs, [
      :provider,
      :external_id,
      :external_number,
      :ref,
      :status,
      :attempts,
      :last_error,
      :sent_at,
      :warnings,
      :alert,
      :remote_status,
      :remote_status_code,
      :remote_status_at
    ])
    |> validate_required([:provider, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:remote_status, @remote_statuses)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end
end
