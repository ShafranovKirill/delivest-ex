defmodule Delivest.Integrations.YandexAds.Identity do
  use Ecto.Schema
  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "yandex_ads_identities" do
    field :branch_id, Ecto.UUID
    field :owner_key, :string
    field :claimed_client_id, Ecto.UUID
    field :generation, :integer
    field :client_id, :string
    field :yclid, :string
    field :campaign_id, :string
    field :ad_id, :string
    field :captured_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end
