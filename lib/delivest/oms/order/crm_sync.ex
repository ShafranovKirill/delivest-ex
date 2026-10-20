defmodule Delivest.Oms.Order.CrmSync do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending sent failed)

  @primary_key false
  embedded_schema do
    field :provider, :string
    field :external_id, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :sent_at, :utc_datetime
  end

  def changeset(sync, attrs) do
    sync
    |> cast(attrs, [:provider, :external_id, :status, :attempts, :last_error, :sent_at])
    |> validate_required([:provider, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end
end
