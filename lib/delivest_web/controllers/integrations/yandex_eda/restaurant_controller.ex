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

  def zones(conn, %{"restaurant_id" => id}), do: reply(conn, YandexEda.zones(id))

  def zone_meta(conn, %{"restaurant_id" => id}), do: reply(conn, YandexEda.zone_metas(id))

  defp reply(conn, {:ok, body}), do: json(conn, body)
  defp reply(conn, {:error, reason}), do: Reply.failure(conn, reason)
end
