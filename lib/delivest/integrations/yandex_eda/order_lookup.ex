defmodule Delivest.Integrations.YandexEda.OrderLookup do
  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Repo

  @provider "yandex_eda"

  def by_eats_id(eats_id) do
    from(o in Order,
      where:
        fragment(
          "?->>'provider' = ? AND ?->>'external_id' = ?",
          o.channel,
          ^@provider,
          o.channel,
          ^eats_id
        )
    )
    |> Repo.one()
  end

  def fetch(order_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{} = order <-
           Repo.one(from(o in Order, where: o.id == ^uuid and o.source == ^@provider)) do
      {:ok, Repo.preload(order, items: :modifiers)}
    else
      _ -> {:error, :order_not_found}
    end
  end
end
