defmodule DelivestWeb.Integrations.YookassaWebhookController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.Yookassa.Webhook

  def create(conn, %{"token" => token} = params) do
    case Webhook.handle(token, params) do
      :ok -> json(conn, %{result: "ok"})
      {:error, _reason} -> conn |> put_status(:not_found) |> json(%{result: "error"})
    end
  end
end
