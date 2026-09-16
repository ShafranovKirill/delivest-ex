defmodule DelivestWeb.Schemas.OrderSchemas do
  alias OpenApiSpex.Schema

  defmodule AddressRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AddressRequest",
      type: :object,
      properties: %{
        city: %Schema{type: :string, example: "Москва", nullable: true},
        street: %Schema{type: :string, example: "Ленина", nullable: true},
        house: %Schema{type: :string, example: "10", nullable: true},
        apartment: %Schema{type: :string, example: "12", nullable: true},
        floor: %Schema{type: :string, example: "3", nullable: true},
        entrance: %Schema{type: :string, example: "2", nullable: true},
        intercom: %Schema{type: :string, example: "42", nullable: true}
      }
    })
  end

  defmodule CreateOrderRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateOrderRequest",
      type: :object,
      properties: %{
        cart_id: %Schema{
          type: :string,
          format: :uuid,
          example: "8f3b2c10-91ab-4cd2-81e2-123456789abc",
          description: "UUID корзины"
        },
        branch_id: %Schema{
          type: :string,
          format: :uuid,
          example: "7b45ded3-881e-4270-bc93-0ad6a904ec53",
          description: "UUID филиала"
        },
        customer_phone: %Schema{
          type: :string,
          example: "+79990000000",
          nullable: true,
          description: "Телефон клиента для поиска/создания клиента"
        },
        customer_name: %Schema{
          type: :string,
          example: "Иван",
          nullable: true,
          description: "Имя клиента"
        },
        fulfillment_type: %Schema{
          type: :string,
          enum: ["dine_in", "delivery", "pickup"],
          example: "delivery",
          nullable: true
        },
        payment_method: %Schema{
          type: :string,
          enum: ["cash", "card_offline"],
          example: "cash",
          nullable: true
        },
        comment: %Schema{
          type: :string,
          example: "Без лука",
          nullable: true
        },
        address: AddressRequest
      },
      required: [:cart_id, :branch_id]
    })
  end

  defmodule OrderItemResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "OrderItemResponse",
      type: :object,
      properties: %{
        product_id: %Schema{
          type: :string,
          format: :uuid,
          example: "c4a3b8e0-1234-5678-9abc-def012345678"
        },
        title: %Schema{type: :string, example: "Пицца Маргарита"},
        price: %Schema{type: :integer, example: 590},
        quantity: %Schema{type: :integer, example: 2}
      },
      required: [:product_id, :title, :price, :quantity]
    })
  end

  defmodule OrderResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.OrderItemResponse

    OpenApiSpex.schema(%{
      title: "OrderResponse",
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
            number: %Schema{type: :string, example: "ORD-1001"},
            status: %Schema{type: :string, example: "created"},
            fulfillment_type: %Schema{type: :string, example: "delivery"},
            payment_method: %Schema{type: :string, example: "cash"},
            total_amount: %Schema{type: :integer, example: 1180},
            branch_id: %Schema{
              type: :string,
              format: :uuid,
              example: "7b45ded3-881e-4270-bc93-0ad6a904ec53"
            },
            cart_id: %Schema{
              type: :string,
              format: :uuid,
              example: "8f3b2c10-91ab-4cd2-81e2-123456789abc"
            },
            client_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true,
              example: "c4a3b8e0-1234-5678-9abc-def012345678"
            },
            comment: %Schema{type: :string, nullable: true, example: "Без лука"},
            customer_phone: %Schema{type: :string, nullable: true, example: "+79990000000"},
            customer_name: %Schema{type: :string, nullable: true, example: "Иван"},
            address: %Schema{type: :object, nullable: true, additionalProperties: true},
            items: %Schema{type: :array, items: OrderItemResponse}
          },
          required: [:id, :number, :status, :total_amount, :branch_id, :cart_id, :items]
        }
      },
      required: [:data]
    })
  end
end
