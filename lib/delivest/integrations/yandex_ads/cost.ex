defmodule Delivest.Integrations.YandexAds.Cost do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "yandex_ads_costs" do
    field :generation, :integer
    field :account, :string
    field :day, :date
    field :campaign_id, :string
    field :campaign_name, :string
    field :cost_micros, :integer
    field :impressions, :integer
    field :clicks, :integer
    field :currency, :string
    field :include_vat, :boolean
    field :updated_at, :utc_datetime_usec
  end
end
