defmodule DelivestWeb.Integrations.ZvonokWebhookController do
  use DelivestWeb, :controller

  require Logger

  alias Delivest.Identity
  alias Delivest.Integrations.Zvonok

  def create(conn, %{"token" => token} = params) do
    received = inspect(conn.query_params)

    if Zvonok.valid_webhook_token?(token) do
      call_id = params["call_id"] || params["ct_call_id"]
      phone = params["phone"] || params["ct_phone"]

      case Identity.confirm_client_call(call_id, phone) do
        :ok ->
          Logger.info("zvonok webhook confirmed call #{call_id} from #{phone}")
          json(conn, %{result: "success"})

        {:error, _reason} ->
          Logger.warning(
            "zvonok webhook matched no pending sign-in (call_id: #{inspect(call_id)}, phone: #{inspect(phone)}), received #{received}"
          )

          json(conn, %{result: "ignored"})
      end
    else
      Logger.warning("zvonok webhook with an unknown token, received #{received}")
      conn |> put_status(:not_found) |> json(%{result: "error"})
    end
  end
end
