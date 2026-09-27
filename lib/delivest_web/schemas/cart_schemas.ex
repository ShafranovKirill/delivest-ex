defmodule DelivestWeb.Schemas.CartSchemas do
  alias OpenApiSpex.Schema

  defmodule AddItemRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AddItemRequest",
      type: :object,
      properties: %{
        product_id: %Schema{
          type: :string,
          format: :uuid,
          example: "c4a3b8e0-1234-5678-9abc-def012345678"
        }
      },
      required: [:product_id]
    })
  end

  defmodule CartItemResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CartItemResponse",
      type: :object,
      properties: %{
        product_id: %Schema{
          type: :string,
          format: :uuid,
          example: "c4a3b8e0-1234-5678-9abc-def012345678"
        },
        name: %Schema{type: :string, example: "Пицца Маргарита"},
        image_url: %Schema{
          type: :string,
          example: "https://example.com/images/pizza.jpg",
          nullable: true
        },
        price: %Schema{
          type: :integer,
          example: 590,
          description: "Цена за единицу в копейках/рублях"
        },
        quantity: %Schema{type: :integer, example: 2},
        total_price: %Schema{
          type: :integer,
          example: 1180,
          description: "Итоговая стоимость позиций"
        }
      },
      required: [:product_id, :name, :price, :quantity, :total_price]
    })
  end

  defmodule CartResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.CartSchemas.CartItemResponse

    OpenApiSpex.schema(%{
      title: "CartResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            id: %Schema{
              type: :string,
              format: :uuid,
              example: "8f3b2c10-91ab-4cd2-81e2-123456789abc"
            },
            session_id: %Schema{
              type: :string,
              example: "eceaec3d-dd25-4e19-8afc-f1d0f1412c9c",
              nullable: true
            },
            branch_id: %Schema{
              type: :string,
              format: :uuid,
              example: "7b45ded3-881e-4270-bc93-0ad6a904ec53",
              nullable: true
            },
            items: %Schema{type: :array, items: CartItemResponse},
            total_quantity: %Schema{type: :integer, example: 3},
            total_amount: %Schema{type: :integer, example: 1500}
          },
          required: [:id, :items, :total_quantity, :total_amount]
        }
      },
      required: [:data]
    })
  end
end
