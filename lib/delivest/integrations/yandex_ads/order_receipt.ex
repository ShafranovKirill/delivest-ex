defmodule Delivest.Integrations.YandexAds.OrderReceipt do
  use Ecto.Schema
  @primary_key {:order_id, Ecto.UUID, autogenerate: false}
  schema "yandex_ads_order_receipts" do
    field :branch_id, Ecto.UUID
    field :generation, :integer
    field :counter_id, :string
    field :client_id, :string
    field :yclid, :string
    field :campaign_id, :string
    field :ad_id, :string
    field :landing_branch_id, Ecto.UUID
    field :captured_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
