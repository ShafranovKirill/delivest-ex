defmodule DelivestWeb.Integrations.CrmWebhookController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.Crm

  def create(conn, %{"provider" => provider, "token" => token} = params) do
    case Crm.handle_webhook(provider, token, params) do
      {:ok, body} -> json(conn, body)
      {:error, reason} -> conn |> put_status(status(reason)) |> json(%{result: "error"})
    end
  end

  defp status(reason) when reason in [:not_found, :unknown_provider], do: :not_found
  defp status(_reason), do: :unprocessable_entity
end
