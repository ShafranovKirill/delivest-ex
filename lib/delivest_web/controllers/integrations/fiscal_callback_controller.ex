defmodule DelivestWeb.Integrations.FiscalCallbackController do
  use DelivestWeb, :controller

  alias Delivest.Fiscal

  def create(conn, %{"provider" => provider, "token" => token} = params) do
    case Fiscal.handle_callback(provider, token, params) do
      {:ok, _receipt} -> json(conn, %{result: "ok"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{result: "error"})
      {:error, _reason} -> conn |> put_status(:unprocessable_entity) |> json(%{result: "error"})
    end
  end
end
