defmodule DelivestWeb.Integrations.YandexEda.OrderController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Integrations.YandexEda.Reply

  def create(conn, params) do
    case YandexEda.create_order(params) do
      {:ok, order} -> json(conn, %{result: "OK", orderId: order.id})
      {:error, {:unavailable, items}} -> Reply.unavailable(conn, items)
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def show(conn, %{"id" => id}) do
    case YandexEda.get_order(id) do
      {:ok, order} -> Reply.typed(conn, "vnd.eats.order.v2", order.channel.details["request"])
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def update(conn, _params),
    do:
      Reply.errors(conn, :unprocessable_entity, :not_supported, "Order changes are not supported")

  def delete(conn, %{"id" => id} = params) do
    case YandexEda.cancel_order(id, params["comment"]) do
      {:ok, _order} -> send_resp(conn, :ok, "")
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def status(conn, %{"id" => id}) do
    case YandexEda.order_status(id) do
      {:ok, status} -> json(conn, status)
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def update_status(conn, %{"id" => id} = params) do
    case YandexEda.update_order_status(id, params) do
      {:ok, _order} -> send_resp(conn, :no_content, "")
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def courier(conn, %{"id" => id} = params) do
    case YandexEda.update_courier(id, params) do
      {:ok, _order} -> send_resp(conn, :no_content, "")
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end

  def feedback(conn, params) do
    case YandexEda.save_feedback(params) do
      {:ok, _order} -> json(conn, %{result: "OK"})
      {:error, reason} -> Reply.failure(conn, reason)
    end
  end
end
