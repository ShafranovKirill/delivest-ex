defmodule DelivestWeb.Client.Storefront.BootstrapController do
  use DelivestWeb, :controller

  def open_api_operation(action), do: DelivestWeb.ApiContracts.operation(__MODULE__, action)

  alias Delivest.Storefront

  def show(conn, params) do
    case Storefront.bootstrap(params) do
      {:ok, response} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(response)

      {:error, :not_found} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:not_found)
        |> json(%{error: "branch_not_found"})

      {:error, _} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("retry-after", "1")
        |> put_status(:service_unavailable)
        |> json(%{error: "storefront_unavailable"})
    end
  end

  def manifest(conn, %{"branch_id" => branch_id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Storefront.manifest(branch_id) do
      {:ok, response} -> json(conn, response)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "branch_not_found"})
      _ -> conn |> put_status(:service_unavailable) |> json(%{error: "storefront_unavailable"})
    end
  end

  def manifest(conn, _params),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_status(:bad_request)
      |> json(%{error: "branch_id_required"})
end
