defmodule DelivestWeb.Integrations.FrontpadWebhookController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.Frontpad.Webhook

  def create(
        conn,
        %{"token" => token, "action" => "change_status", "order_id" => order_id} = params
      ) do
    case Webhook.change_status(token, order_id, params["status"], params["datetime"]) do
      {:ok, _order} -> json(conn, %{result: "success"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{result: "error"})
      {:error, _reason} -> conn |> put_status(:unprocessable_entity) |> json(%{result: "error"})
    end
  end

  def create(conn, _params), do: json(conn, %{result: "ignored"})
end
