defmodule Delivest.Integrations.YandexAds.Conversion do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "yandex_ads_conversions" do
    field :order_id, Ecto.UUID
    field :branch_id, Ecto.UUID
    field :generation, :integer
    field :counter_id, :string
    field :channel, :string
    field :status, :string, default: "pending"
    field :reason, :string
    field :amount, :integer
    field :occurred_at, :utc_datetime_usec
    field :payload, :map, default: %{}
    field :upload_id, :string
    field :provider_status, :string
    field :attempted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
