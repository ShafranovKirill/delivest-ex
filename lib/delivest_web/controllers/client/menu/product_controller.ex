defmodule DelivestWeb.Client.Menu.ProductController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Net.PublicOffers
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.MenuSchemas.ProductResponse
  alias OpenApiSpex.Schema

  operation(:show,
    summary: "Получить один публичный товар филиала",
    tags: ["Menu"],
    parameters: [
      branch_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      product_key: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    responses: [
      ok:
        {"Товар с текущей ценой, модификаторами и доступностью", "application/json",
         %Schema{type: :object, properties: %{data: ProductResponse}}},
      not_found: {"Товар недоступен в этом филиале", "application/json", ErrorResponse}
    ]
  )

  def show(conn, %{"branch_id" => branch_id, "product_key" => key}) do
    case PublicOffers.product(branch_id, key) do
      {:ok, product} ->
        conn |> put_resp_header("cache-control", "no-store") |> json(%{data: product})

      {:error, :not_found} ->
        ApiError.send_error(conn, :not_found, :product_unavailable, "Product not found")
    end
  end
end
