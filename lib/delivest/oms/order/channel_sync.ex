defmodule Delivest.Oms.Order.ChannelSync do
  use Ecto.Schema
  import Ecto.Changeset

  @remote_statuses ~w(delivering completed cancelled)

  @primary_key false
  embedded_schema do
    field :provider, :string
    field :external_id, :string
    field :external_number, :string
    field :platform, :string
    field :delivery, :string
    field :remote_status, :string
    field :remote_status_at, :utc_datetime
    field :details, :map, default: %{}
  end

  def remote_statuses, do: @remote_statuses

  def changeset(sync, attrs) do
    sync
    |> cast(attrs, [
      :provider,
      :external_id,
      :external_number,
      :platform,
      :delivery,
      :remote_status,
      :remote_status_at,
      :details
    ])
    |> validate_required([:provider, :external_id])
    |> validate_inclusion(:remote_status, @remote_statuses)
  end
end
