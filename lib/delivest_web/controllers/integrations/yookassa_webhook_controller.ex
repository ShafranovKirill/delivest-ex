defmodule DelivestWeb.Integrations.YookassaWebhookController do
  use DelivestWeb, :controller

  def open_api_operation(action), do: DelivestWeb.ApiContracts.operation(__MODULE__, action)

  alias Delivest.Integrations.Yookassa.Webhook

  def create(conn, %{"token" => token} = params) do
    case Webhook.handle(token, params) do
      :ok -> json(conn, %{result: "ok"})
      {:error, _reason} -> conn |> put_status(:not_found) |> json(%{result: "error"})
    end
  end
end
