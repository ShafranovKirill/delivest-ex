defmodule DelivestWeb.Client.Stock.StockController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Net
  alias DelivestWeb.Schemas.StockSchemas.StocksListResponse
  alias OpenApiSpex.Schema

  operation(:index,
    summary: "Получить список активных акций филиала",
    description: "Возвращает список всех активных акций, привязанных к данному branch_id",
    parameters: [
      branch_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "UUID филиала",
        required: true,
        example: "123e4567-e89b-12d3-a456-426614174000"
      ]
    ],
    responses: [
      ok: {"Список акций", "application/json", StocksListResponse}
    ]
  )

  def index(conn, %{"branch_id" => branch_id}) do
    stocks = Net.list_stocks_for_branch(branch_id)
    render(conn, :index, stocks: stocks)
  end
end
