defmodule Delivest.Integrations.YandexDelivery.Journal do
  use Ecto.Schema

  @primary_key {:branch_id, :binary_id, autogenerate: false}

  schema "yandex_delivery_journals" do
    field :cursor, :string

    timestamps(type: :utc_datetime_usec)
  end
end
