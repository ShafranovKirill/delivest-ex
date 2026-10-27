defmodule DelivestWeb.Integrations.YandexEda.RestaurantController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Integrations.YandexEda.Reply

  def index(conn, _params), do: json(conn, %{places: YandexEda.restaurants()})

  def availability(conn, _params), do: json(conn, %{places: YandexEda.restaurants_availability()})

  def schedule(conn, %{"restaurant_id" => id}) do
    case YandexEda.schedule(id) do
      {:ok, schedule} -> json(conn, schedule)
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end
end
