defmodule DelivestWeb.Integrations.ZvonokWebhookController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.Integrations.Zvonok

  def create(conn, %{"token" => token} = params) do
    if Zvonok.valid_webhook_token?(token) do
      json(conn, %{
        result: result(Identity.confirm_client_call(params["call_id"], params["phone"]))
      })
    else
      conn |> put_status(:not_found) |> json(%{result: "error"})
    end
  end

  defp result(:ok), do: "success"
  defp result({:error, _reason}), do: "ignored"
end
