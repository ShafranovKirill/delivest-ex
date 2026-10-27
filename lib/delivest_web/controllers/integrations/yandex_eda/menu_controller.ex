defmodule DelivestWeb.Integrations.YandexEda.MenuController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Integrations.YandexEda.Reply

  def composition(conn, %{"restaurant_id" => id}) do
    case YandexEda.composition(id) do
      {:ok, menu} -> Reply.typed(conn, "vnd.eats.menu.composition.v2", menu)
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def availability(conn, %{"restaurant_id" => id}) do
    case YandexEda.availability(id) do
      {:ok, stops} -> Reply.typed(conn, "vnd.eats.menu.availability.v2", stops)
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end
end
