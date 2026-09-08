defmodule DelivestWeb.Schemas.StockSchemas do
  alias OpenApiSpex.Schema

  defmodule StockResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StockResponse",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          example: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
        },
        text: %Schema{
          type: :string,
          example: "Скидка 20% на первую покупку",
          description: "Текст или описание акции"
        },
        is_active: %Schema{
          type: :boolean,
          example: true,
          description: "Флаг активности акции"
        },
        order: %Schema{type: :number, format: :float, example: 1.0},
        photo_url: %Schema{
          type: :string,
          format: :uri,
          nullable: true,
          example: "https://storage.example.com/images/stock.jpg",
          description: "Ссылка на медиафайл акции"
        }
      }
    })
  end

  defmodule StocksListResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.StockSchemas.StockResponse

    OpenApiSpex.schema(%{
      title: "StocksListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: StockResponse}
      }
    })
  end
end
